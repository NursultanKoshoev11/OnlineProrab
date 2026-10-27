#!/usr/bin/env bash
set -Eeuo pipefail

release_sha="${1:?release SHA is required}"
deploy_root="${2:?deployment directory is required}"
operation="${3:-deploy}"

if [[ "$operation" != deploy && "$operation" != rollback && "$operation" != finalize ]]; then
  echo "Invalid deployment operation" >&2
  exit 2
fi
if [[ ! "$release_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Invalid release SHA" >&2
  exit 2
fi
if [[ ! "$deploy_root" =~ ^/[A-Za-z0-9._/-]+$ || "$deploy_root" == / || "$deploy_root" == */ || "$deploy_root" == *//* || "$deploy_root" == *'/../'* || "$deploy_root" == */.. || "$deploy_root" == *'/./'* || "$deploy_root" == */. ]]; then
  echo "Deployment directory must be a normalized absolute path" >&2
  exit 2
fi
if [[ -L "$deploy_root" || ! -d "$deploy_root" ]]; then
  echo "Deployment directory must already exist and must not be a symbolic link" >&2
  exit 2
fi
resolved_deploy_root="$(cd -P "$deploy_root" && pwd -P)"
if [[ "$resolved_deploy_root" != "$deploy_root" ]]; then
  echo "Deployment directory path must not contain symbolic links" >&2
  exit 2
fi

releases_dir="$deploy_root/releases"
release_dir="$releases_dir/$release_sha"
compose_file="$release_dir/website/docker-compose.billing.yml"
source_archive="/tmp/stroy-obank-billing-$release_sha.source.tar.gz"
rollback_dir="$deploy_root/.billing-rollback"
rollback_state_file="$rollback_dir/$release_sha"
rollback_image_tag="stroy-obank-billing:rollback-$release_sha"
production_image_tag="stroy-obank-billing:production"
previous_image_id=""
state_tmp=""
deployment_started=0

if [[ -L "$releases_dir" || ! -d "$releases_dir" || -L "$release_dir" || ! -d "$release_dir" || -L "$release_dir/website" || ! -d "$release_dir/website" ]]; then
  echo "The production website release directory is missing or unsafe" >&2
  exit 2
fi

read_rollback_state() {
  if [[ -L "$rollback_dir" || ! -d "$rollback_dir" || -L "$rollback_state_file" || ! -f "$rollback_state_file" ]]; then
    echo "No safe billing rollback state exists for revision $release_sha" >&2
    return 2
  fi
  local -a state=()
  mapfile -t state < "$rollback_state_file"
  if [[ "${#state[@]}" -ne 1 ]]; then
    echo "Billing rollback state is malformed for revision $release_sha" >&2
    return 2
  fi
  previous_image_id="${state[0]}"
  if [[ "$previous_image_id" != none && ! "$previous_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Previous billing image identifier is invalid" >&2
    return 2
  fi
}

restore_previous_billing() {
  if [[ "$previous_image_id" == none ]]; then
    docker rm --force stroy-obank-billing >/dev/null 2>&1 || true
    return 0
  fi

  if ! docker image inspect "$rollback_image_tag" >/dev/null 2>&1; then
    docker image tag "$previous_image_id" "$rollback_image_tag"
  fi
  docker image tag "$rollback_image_tag" "$production_image_tag"
  docker rm --force stroy-obank-billing >/dev/null 2>&1 || true
  docker compose -p stroy-billing -f "$compose_file" -f <(printf 'services:\n  billing:\n    healthcheck:\n      disable: true\n') up --detach --no-build --force-recreate --wait --wait-timeout 120
}

cleanup() {
  local status=$?
  trap - EXIT

  if (( status != 0 && deployment_started == 1 )); then
    echo "Billing deploy failed; restoring its previous image" >&2
    if restore_previous_billing; then
      rm -f "$rollback_state_file"
      docker image rm --force "$rollback_image_tag" >/dev/null 2>&1 || true
    else
      echo "Billing rollback failed; inspect stroy-obank-billing and $rollback_state_file" >&2
    fi
  fi

  rm -f "$source_archive"
  if [[ -n "$state_tmp" ]]; then
    rm -f "$state_tmp"
  fi
  exit "$status"
}

case "$operation" in
  rollback)
    read_rollback_state
    if [[ ! -f "$compose_file" || -L "$compose_file" ]]; then
      echo "Billing Compose file is missing or unsafe" >&2
      exit 2
    fi
    if docker inspect stroy-obank-billing >/dev/null 2>&1; then
      current_revision="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' stroy-obank-billing)"
      if [[ "$current_revision" != "$release_sha" ]]; then
        echo "Billing container revision changed; refusing stale rollback" >&2
        exit 2
      fi
    else
      echo "Billing container is missing; refusing rollback" >&2
      exit 2
    fi
    restore_previous_billing
    rm -f "$rollback_state_file"
    docker image rm --force "$rollback_image_tag" >/dev/null 2>&1 || true
    echo "Rolled back billing revision $release_sha"
    exit 0
    ;;
  finalize)
    read_rollback_state
    if docker inspect stroy-obank-billing >/dev/null 2>&1; then
      current_revision="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' stroy-obank-billing)"
      if [[ "$current_revision" != "$release_sha" ]]; then
        echo "Billing container revision changed; refusing to finalize stale state" >&2
        exit 2
      fi
    else
      echo "Billing container is missing; refusing to finalize" >&2
      exit 2
    fi
    rm -f "$rollback_state_file"
    docker image rm --force "$rollback_image_tag" >/dev/null 2>&1 || true
    rmdir "$rollback_dir" 2>/dev/null || true
    echo "Finalized billing revision $release_sha"
    exit 0
    ;;
  deploy)
    ;;
esac

if [[ ! -f "$source_archive" || -L "$source_archive" ]]; then
  echo "Billing deployment archive is missing or unsafe" >&2
  exit 2
fi
source_members="$(tar -tzf "$source_archive")"
if [[ "$source_members" != "website/docker-compose.billing.yml" ]]; then
  echo "Unexpected paths in billing deployment archive" >&2
  exit 2
fi
if ! tar -tvzf "$source_archive" | awk 'NR == 1 && substr($0, 1, 1) == "-" { valid = 1; next } { invalid = 1 } END { exit invalid || !valid }'; then
  echo "Billing deployment archive may contain only a regular Compose file" >&2
  exit 2
fi
if [[ -L "$compose_file" || ( -e "$compose_file" && ! -f "$compose_file" ) ]]; then
  echo "Billing Compose path exists but is not a regular file" >&2
  exit 2
fi

tar -xzf "$source_archive" -C "$release_dir"
if [[ ! -f "$compose_file" || -L "$compose_file" ]]; then
  echo "Billing Compose file was not safely extracted" >&2
  exit 2
fi
docker compose -p stroy-billing -f "$compose_file" config --quiet
if [[ "$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$production_image_tag")" != "$release_sha" ]]; then
  echo "Billing image does not match release revision $release_sha" >&2
  exit 2
fi

if [[ -L "$rollback_dir" || ( -e "$rollback_dir" && ! -d "$rollback_dir" ) ]]; then
  echo "Billing rollback state path must be a regular directory" >&2
  exit 2
fi
mkdir -m 700 -p "$rollback_dir"
chmod 700 "$rollback_dir"
if [[ -e "$rollback_state_file" || -L "$rollback_state_file" ]]; then
  echo "A billing rollback window already exists for revision $release_sha" >&2
  exit 2
fi

if docker inspect stroy-obank-billing >/dev/null 2>&1; then
  previous_image_id="$(docker inspect --format '{{.Image}}' stroy-obank-billing)"
  if [[ ! "$previous_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Previous billing image identifier is invalid" >&2
    exit 2
  fi
  docker image tag "$previous_image_id" "$rollback_image_tag"
else
  previous_image_id=none
fi

state_tmp="$(mktemp "$rollback_dir/.$release_sha.tmp.XXXXXX")"
printf '%s\n' "$previous_image_id" > "$state_tmp"
chmod 600 "$state_tmp"
mv -T "$state_tmp" "$rollback_state_file"
state_tmp=""
deployment_started=1
trap cleanup EXIT

docker rm --force stroy-obank-billing >/dev/null 2>&1 || true
docker compose -p stroy-billing -f "$compose_file" up --detach --no-build --force-recreate --wait --wait-timeout 120

current_revision="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' stroy-obank-billing)"
if [[ "$current_revision" != "$release_sha" ]]; then
  echo "Billing container revision does not match deployment" >&2
  exit 1
fi

trap - EXIT
rm -f "$source_archive"
echo "Deployed billing revision $release_sha"
