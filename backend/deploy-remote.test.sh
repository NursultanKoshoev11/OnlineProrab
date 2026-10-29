#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
deploy_script="$script_dir/deploy-remote.sh"
temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin"
cat > "$temporary_dir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FAKE_DOCKER_MODE:-reject}" != "deploy" ]]; then
  echo "docker must not be called for rejected deployment input" >&2
  exit 99
fi

case "${1:-}" in
  ps)
    exit 0
    ;;
  load)
    exit 0
    ;;
  image)
    if [[ "${2:-}" == "inspect" && "${3:-}" == "--format" ]]; then
      printf '%s\n' "$VALID_SHA"
      exit 0
    fi
    ;;
  compose)
    if [[ "${API_IMAGE:-}" != "stroy-api:$VALID_SHA" ]]; then
      echo "compose received an unexpected API image" >&2
      exit 98
    fi
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac

echo "unexpected docker invocation: $*" >&2
exit 98
DOCKER
chmod +x "$temporary_dir/bin/docker"
export PATH="$temporary_dir/bin:$PATH"

valid_sha=0123456789abcdef0123456789abcdef01234567
deploy_root="$temporary_dir/api"
mkdir -p "$deploy_root"
: > "$deploy_root/.env"
chmod 600 "$deploy_root/.env"

case_number=0
expect_rejection() {
  local expected_message="$1"
  shift
  case_number=$((case_number + 1))
  local output="$temporary_dir/case-$case_number.log"
  local status=0
  if bash "$deploy_script" "$@" >"$output" 2>&1; then
    echo "expected deployment script to reject case $case_number" >&2
    exit 1
  else
    status="$?"
  fi
  if [[ "$status" == "99" ]]; then
    cat "$output" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_message" "$output"; then
    cat "$output" >&2
    echo "rejection did not explain case $case_number" >&2
    exit 1
  fi
}

expect_rejection "deployment revision must be a full lowercase commit SHA" deploy bad "$deploy_root" api-production
expect_rejection "Compose project name contains unsupported characters" deploy "$valid_sha" "$deploy_root" "api;production"

chmod 644 "$deploy_root/.env"
expect_rejection "deployment .env must not be readable or writable by group or other users" deploy "$valid_sha" "$deploy_root" api-production
chmod 600 "$deploy_root/.env"

ln -s "$deploy_root" "$temporary_dir/api-link"
expect_rejection "deployment path must already exist as a canonical directory" deploy "$valid_sha" "$temporary_dir/api-link" api-production

mkdir -p "$deploy_root/releases" "$temporary_dir/outside"
ln -s ../outside "$deploy_root/current"
expect_rejection "current release pointer is not a canonical managed release" rollback "$valid_sha" "$deploy_root" api-production

successful_root="$temporary_dir/successful-api"
mkdir -p "$successful_root"
: > "$successful_root/.env"
chmod 600 "$successful_root/.env"
image_archive="/tmp/stroy-api-$valid_sha.image.tar.gz"
compose_file="/tmp/stroy-api-$valid_sha.compose.yml"
backup_script="/tmp/stroy-api-$valid_sha.backup.sh"
safe_path_script="/tmp/stroy-api-$valid_sha.safe-path.sh"
fcm_secret_file="/tmp/stroy-api-$valid_sha.fcm.json"
for artifact in "$image_archive" "$compose_file" "$fcm_secret_file" "$backup_script" "$safe_path_script"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    echo "deployment test artifact already exists: $artifact" >&2
    exit 1
  fi
done
trap 'rm -rf -- "$temporary_dir"; rm -f -- "$image_archive" "$compose_file" "$fcm_secret_file" "$backup_script" "$safe_path_script"' EXIT
printf '%s' fake-image | gzip -c > "$image_archive"
printf '%s\n' 'services: {}' > "$compose_file"
printf '%s\n' '{"project_id":"stroy-notifications"}' > "$fcm_secret_file"
cp "$script_dir/scripts/backup.sh" "$backup_script"
cp "$script_dir/scripts/safe-path.sh" "$safe_path_script"
docker_log="$temporary_dir/docker.log"
if ! FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$docker_log" \
  bash "$deploy_script" deploy "$valid_sha" "$successful_root" api-production; then
  echo "expected deployment fixture to succeed" >&2
  exit 1
fi
if [[ "$(readlink -- "$successful_root/current")" != "releases/$valid_sha" ]]; then
  echo "successful deployment did not activate its managed release" >&2
  exit 1
fi
if ! cmp -s "$script_dir/scripts/backup.sh" "$successful_root/releases/$valid_sha/backend/scripts/backup.sh" || \
  ! cmp -s "$script_dir/scripts/safe-path.sh" "$successful_root/releases/$valid_sha/backend/scripts/safe-path.sh"; then
  echo "successful deployment did not install the matching backup scripts" >&2
  exit 1
fi
if [[ "$(stat -c '%a' "$successful_root/releases/$valid_sha/backend/scripts/backup.sh")" != "644" || \
  "$(stat -c '%a' "$successful_root/releases/$valid_sha/backend/scripts/safe-path.sh")" != "644" ]]; then
  echo "deployed backup scripts have unexpected permissions" >&2
  exit 1
fi
if ! grep -Fq 'up --detach --no-build --pull never --wait --wait-timeout 180 api' "$docker_log"; then
  echo "successful deployment did not start the API release" >&2
  exit 1
fi
for artifact in "$image_archive" "$compose_file" "$fcm_secret_file" "$backup_script" "$safe_path_script"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    echo "deployment left a transferred artifact behind: $artifact" >&2
    exit 1
  fi
done

echo "Backend deployment guards and release installation passed."
