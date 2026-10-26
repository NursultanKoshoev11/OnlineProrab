#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-}"
deploy_sha="${2:-}"
deploy_path="${3:-}"
compose_project="${4:-}"

if [[ "$mode" != "deploy" && "$mode" != "rollback" ]]; then
  echo "usage: deploy-remote.sh deploy|rollback <40-character-sha> <absolute-deploy-path> <compose-project>" >&2
  exit 2
fi
if [[ ! "$deploy_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "deployment revision must be a full lowercase commit SHA" >&2
  exit 2
fi
if [[ ! "$deploy_path" =~ ^/[A-Za-z0-9._/-]+$ || "$deploy_path" == "/" || "$deploy_path" == */ || "$deploy_path" == *"//"* || "$deploy_path" == *"/../"* || "$deploy_path" == */.. || "$deploy_path" == *"/./"* || "$deploy_path" == */. ]]; then
  echo "deployment path is not a normalized absolute path" >&2
  exit 2
fi
if [[ ! "$compose_project" =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]]; then
  echo "Compose project name contains unsupported characters" >&2
  exit 2
fi
if [[ ! -d "$deploy_path" || -L "$deploy_path" || "$(realpath -e -- "$deploy_path")" != "$deploy_path" ]]; then
  echo "deployment path must already exist as a canonical directory" >&2
  exit 1
fi

env_file="$deploy_path/.env"
current_link="$deploy_path/current"
releases_dir="$deploy_path/releases"
if [[ ! -f "$env_file" || -L "$env_file" || "$(stat -c '%u' -- "$env_file")" != "$(id -u)" ]]; then
  echo "deployment .env must be a regular file owned by the deploy user" >&2
  exit 1
fi
env_mode="$(stat -c '%a' -- "$env_file")"
if (( (8#$env_mode & 077) != 0 )); then
  echo "deployment .env must not be readable or writable by group or other users" >&2
  exit 1
fi
if [[ -e "$releases_dir" && ( ! -d "$releases_dir" || -L "$releases_dir" ) ]]; then
  echo "releases path must be a real directory" >&2
  exit 1
fi
mkdir -p -- "$releases_dir"
if [[ "$(realpath -e -- "$releases_dir")" != "$releases_dir" ]]; then
  echo "releases path resolves outside the deployment root" >&2
  exit 1
fi
lock_file="$deploy_path/.deploy.lock"
if [[ -e "$lock_file" && ( ! -f "$lock_file" || -L "$lock_file" || "$(stat -c '%u' -- "$lock_file")" != "$(id -u)" ) ]]; then
  echo "deployment lock must be a regular file owned by the deploy user" >&2
  exit 1
fi
exec 9>>"$lock_file"
if ! flock -n 9; then
  echo "another API deployment or rollback is already running" >&2
  exit 1
fi

release_ref=""
if [[ -L "$current_link" ]]; then
  release_ref="$(readlink -- "$current_link")"
  if [[ ! "$release_ref" =~ ^releases/(baseline|[0-9a-f]{40})$ || ! -d "$deploy_path/$release_ref" || -L "$deploy_path/$release_ref" ]]; then
    echo "current release pointer is not a canonical managed release" >&2
    exit 1
  fi
  if [[ "$(realpath -e -- "$current_link")" != "$deploy_path/$release_ref" ]]; then
    echo "current release pointer resolves outside the deployment root" >&2
    exit 1
  fi
elif [[ -e "$current_link" ]]; then
  echo "current release pointer must be a symlink managed by this deploy script" >&2
  exit 1
fi

validate_image_ref() {
  [[ "$1" =~ ^stroy-api:(baseline|[0-9a-f]{40})$ ]]
}

assert_container_matches_compose() {
  local container_id="$1"
  local image_ref="$2"
  local compose_file="$3"
  local config_file
  local container_file
  config_file="$(mktemp "$deploy_path/.api-compose-config.XXXXXX")"
  if ! container_file="$(mktemp "$deploy_path/.api-running-config.XXXXXX")"; then
    rm -f -- "$config_file"
    return 1
  fi
  if ! compose "$image_ref" "$compose_file" config --format json > "$config_file"; then
    rm -f -- "$config_file" "$container_file"
    echo "could not render the managed API configuration" >&2
    return 1
  fi
  if ! docker inspect --format '{{json .Config.Env}}' "$container_id" > "$container_file"; then
    rm -f -- "$config_file" "$container_file"
    echo "could not inspect the active API configuration" >&2
    return 1
  fi
  local status=0
  if python3 - "$config_file" "$container_file" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as config_file:
        expected = json.load(config_file)["services"]["api"]["environment"]
    with open(sys.argv[2], encoding="utf-8") as container_file:
        entries = json.load(container_file)
except (OSError, KeyError, TypeError, ValueError):
    print("could not compare the active API environment", file=sys.stderr)
    raise SystemExit(1)

actual = {}
for entry in entries:
    key, separator, value = entry.partition("=")
    if separator:
        actual[key] = value
mismatches = [key for key, value in expected.items() if actual.get(key) != str(value)]
if mismatches:
    print("active API environment differs from the prepared release for: " + ", ".join(sorted(mismatches)), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    status=0
  else
    status="$?"
  fi
  rm -f -- "$config_file" "$container_file"
  return "$status"
}
read_release_image() {
  local ref="$1"
  local image_file="$deploy_path/$ref/image-tag"
  [[ -f "$image_file" && ! -L "$image_file" ]] || {
    echo "release image metadata is missing" >&2
    return 1
  }
  local image_ref
  image_ref="$(cat -- "$image_file")"
  validate_image_ref "$image_ref" || {
    echo "release image metadata is invalid" >&2
    return 1
  }
  printf '%s' "$image_ref"
}

compose() {
  local image_ref="$1"
  local compose_file="$2"
  shift 2
  API_IMAGE="$image_ref" docker compose \
    --project-name "$compose_project" \
    --env-file "$env_file" \
    --file "$compose_file" \
    "$@"
}

set_current() {
  local target_ref="$1"
  local temporary_link="$deploy_path/.current-$deploy_sha"
  if [[ -n "$target_ref" && ! "$target_ref" =~ ^releases/(baseline|[0-9a-f]{40})$ ]]; then
    echo "refusing to set an unmanaged current release pointer" >&2
    return 1
  fi
  if [[ -e "$temporary_link" || -L "$temporary_link" ]]; then
    rm -f -- "$temporary_link"
  fi
  if [[ -n "$target_ref" ]]; then
    ln -s "$target_ref" "$temporary_link"
    mv -Tf -- "$temporary_link" "$current_link"
  else
    rm -f -- "$current_link"
  fi
}

rollback_to_previous() {
  local previous_ref="$1"
  local new_compose="$deploy_path/releases/$deploy_sha/backend/docker-compose.prod.yml"
  local new_image="stroy-api:$deploy_sha"
  if [[ -n "$previous_ref" ]]; then
    local previous_compose="$deploy_path/$previous_ref/backend/docker-compose.prod.yml"
    local previous_image
    previous_image="$(read_release_image "$previous_ref")"
    if [[ ! -f "$previous_compose" || -L "$previous_compose" || "$(realpath -e -- "$previous_compose")" != "$previous_compose" ]]; then
      echo "previous API Compose file is missing or resolves outside its release" >&2
      return 1
    fi
    docker image inspect "$previous_image" >/dev/null
    compose "$previous_image" "$previous_compose" up --detach --no-build --pull never --wait --wait-timeout 180 api
    set_current "$previous_ref"
    echo "Restored API release ${previous_ref#releases/}."
  else
    compose "$new_image" "$new_compose" stop --timeout 30 api || true
    compose "$new_image" "$new_compose" rm --force --stop api || true
    set_current ""
    echo "Removed the failed first API release."
  fi
}

if [[ "$mode" == "rollback" ]]; then
  if [[ "$release_ref" != "releases/$deploy_sha" ]]; then
    echo "refusing stale rollback: current release does not match requested revision" >&2
    exit 1
  fi
  previous_file="$deploy_path/releases/$deploy_sha/previous-release"
  [[ -f "$previous_file" && ! -L "$previous_file" ]] || {
    echo "release rollback metadata is missing" >&2
    exit 1
  }
  previous_ref="$(cat -- "$previous_file")"
  if [[ -n "$previous_ref" && ! "$previous_ref" =~ ^releases/(baseline|[0-9a-f]{40})$ ]]; then
    echo "release rollback metadata is invalid" >&2
    exit 1
  fi
  rollback_to_previous "$previous_ref"
  exit 0
fi

backup_script="/tmp/stroy-api-$deploy_sha.backup.sh"
safe_path_script="/tmp/stroy-api-$deploy_sha.safe-path.sh"
if [[ ! -f "/tmp/stroy-api-$deploy_sha.image.tar.gz" || -L "/tmp/stroy-api-$deploy_sha.image.tar.gz" || \
  ! -f "/tmp/stroy-api-$deploy_sha.compose.yml" || -L "/tmp/stroy-api-$deploy_sha.compose.yml" || \
  ! -f "$backup_script" || -L "$backup_script" || \
  ! -f "$safe_path_script" || -L "$safe_path_script" ]]; then
  echo "transferred image, Compose file, or backup scripts are missing" >&2
  exit 1
fi
cleanup_transferred_files() {
  rm -f -- "/tmp/stroy-api-$deploy_sha.image.tar.gz" "/tmp/stroy-api-$deploy_sha.compose.yml" "$backup_script" "$safe_path_script"
}
trap cleanup_transferred_files EXIT

if [[ "$release_ref" == "releases/$deploy_sha" ]]; then
  echo "revision is already the active release" >&2
  exit 1
fi

running_ids="$(docker ps --quiet --filter "label=com.docker.compose.project=$compose_project" --filter 'label=com.docker.compose.service=api')"
if [[ -z "$release_ref" && -n "$running_ids" ]]; then
  if [[ "$(printf '%s\n' "$running_ids" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "expected exactly one existing API container to adopt as the S3-ready baseline" >&2
    exit 1
  fi
  existing_container="$(printf '%s\n' "$running_ids" | head -n 1)"
  assert_container_matches_compose "$existing_container" "stroy-api:baseline" "/tmp/stroy-api-$deploy_sha.compose.yml"
  existing_image_id="$(docker inspect --format '{{.Image}}' "$existing_container")"
  docker image tag "$existing_image_id" stroy-api:baseline
  baseline_release="$deploy_path/releases/baseline"
  if [[ -e "$baseline_release" && ( ! -d "$baseline_release" || -L "$baseline_release" ) ]]; then
    echo "baseline release path must be a real directory" >&2
    exit 1
  fi
  mkdir -p -- "$baseline_release/backend"
  if [[ "$(realpath -e -- "$baseline_release")" != "$baseline_release" || "$(realpath -e -- "$baseline_release/backend")" != "$baseline_release/backend" ]]; then
    echo "baseline release path resolves outside the deployment root" >&2
    exit 1
  fi
  for metadata in "$baseline_release/image-tag" "$baseline_release/previous-release"; do
    if [[ -e "$metadata" && ( ! -f "$metadata" || -L "$metadata" ) ]]; then
      echo "baseline release metadata must be regular files" >&2
      exit 1
    fi
  done
  install -m 0644 -- "/tmp/stroy-api-$deploy_sha.compose.yml" "$baseline_release/backend/docker-compose.prod.yml"
  printf '%s\n' stroy-api:baseline > "$baseline_release/image-tag"
  printf '\n' > "$baseline_release/previous-release"
  set_current "releases/baseline"
  release_ref="releases/baseline"
fi
if [[ -n "$release_ref" ]]; then
  previous_compose="$deploy_path/$release_ref/backend/docker-compose.prod.yml"
  previous_image="$(read_release_image "$release_ref")"
  if [[ ! -f "$previous_compose" || -L "$previous_compose" || "$(realpath -e -- "$previous_compose")" != "$previous_compose" ]]; then
    echo "current release Compose file is missing or resolves outside its release" >&2
    exit 1
  fi
  docker image inspect "$previous_image" >/dev/null
  if [[ "$(printf '%s\n' "$running_ids" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "the current API release must have exactly one running container before replacement" >&2
    exit 1
  fi
  running_container="$(printf '%s\n' "$running_ids" | head -n 1)"
  assert_container_matches_compose "$running_container" "$previous_image" "$previous_compose"
  running_image_id="$(docker inspect --format '{{.Image}}' "$running_container")"
  expected_image_id="$(docker image inspect --format '{{.Id}}' "$previous_image")"
  if [[ "$running_image_id" != "$expected_image_id" ]]; then
    echo "running API image does not match the managed current release" >&2
    exit 1
  fi
fi
release_dir="$deploy_path/releases/$deploy_sha"
if [[ -e "$release_dir" && ( ! -d "$release_dir" || -L "$release_dir" ) ]]; then
  echo "release path must be a real directory" >&2
  exit 1
fi
if [[ -e "$release_dir/backend" && ( ! -d "$release_dir/backend" || -L "$release_dir/backend" ) ]]; then
  echo "release backend path must be a real directory" >&2
  exit 1
fi
mkdir -p -- "$release_dir/backend"
if [[ "$(realpath -e -- "$release_dir")" != "$release_dir" || "$(realpath -e -- "$release_dir/backend")" != "$release_dir/backend" ]]; then
  echo "release path resolves outside the deployment root" >&2
  exit 1
fi
for metadata in "$release_dir/previous-release" "$release_dir/image-tag"; do
  if [[ -e "$metadata" && ( ! -f "$metadata" || -L "$metadata" ) ]]; then
    echo "release metadata must be regular files" >&2
    exit 1
  fi
done
install -m 0644 -- "/tmp/stroy-api-$deploy_sha.compose.yml" "$release_dir/backend/docker-compose.prod.yml"
scripts_dir="$release_dir/backend/scripts"
if [[ -e "$scripts_dir" && ( ! -d "$scripts_dir" || -L "$scripts_dir" ) ]]; then
  echo "release scripts path must be a real directory" >&2
  exit 1
fi
mkdir -p -- "$scripts_dir"
if [[ "$(realpath -e -- "$scripts_dir")" != "$scripts_dir" ]]; then
  echo "release scripts path resolves outside its release" >&2
  exit 1
fi
for release_script in "$scripts_dir/backup.sh" "$scripts_dir/safe-path.sh"; do
  if [[ -e "$release_script" && ( ! -f "$release_script" || -L "$release_script" ) ]]; then
    echo "release backup script must be a regular file" >&2
    exit 1
  fi
done
install -m 0644 -- "$backup_script" "$scripts_dir/backup.sh"
install -m 0644 -- "$safe_path_script" "$scripts_dir/safe-path.sh"
printf '%s\n' "$release_ref" > "$release_dir/previous-release"
printf 'stroy-api:%s\n' "$deploy_sha" > "$release_dir/image-tag"
gzip -t -- "/tmp/stroy-api-$deploy_sha.image.tar.gz"
docker load --input "/tmp/stroy-api-$deploy_sha.image.tar.gz"
image_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "stroy-api:$deploy_sha")"
if [[ "$image_revision" != "$deploy_sha" ]]; then
  echo "loaded API image does not match the requested source revision" >&2
  exit 1
fi

new_compose="$release_dir/backend/docker-compose.prod.yml"
compose "stroy-api:$deploy_sha" "$new_compose" config --quiet

deployment_started=1
deployment_committed=0
on_exit() {
  local exit_code="$?"
  trap - EXIT
  if (( exit_code != 0 && deployment_started == 1 && deployment_committed == 0 )); then
    echo "API health check failed; restoring the previous managed release." >&2
    if ! rollback_to_previous "$release_ref"; then
      echo "automatic API rollback failed; inspect Docker and the production database immediately" >&2
    fi
  fi
  rm -f -- "/tmp/stroy-api-$deploy_sha.image.tar.gz" "/tmp/stroy-api-$deploy_sha.compose.yml" "$backup_script" "$safe_path_script"
  exit "$exit_code"
}
trap on_exit EXIT

compose "stroy-api:$deploy_sha" "$new_compose" up --detach --no-build --pull never --wait --wait-timeout 180 api
set_current "releases/$deploy_sha"
deployment_committed=1
echo "API release $deploy_sha is healthy and active."
