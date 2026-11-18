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

previous_image="${FAKE_PREVIOUS_IMAGE:-}"
case "${1:-}" in
  ps)
    # An existing managed release has exactly one running API container.
    if [[ -n "$previous_image" && "$*" == *"label=com.docker.compose.service=api"* ]]; then
      printf '%s\n' fake-api-container
      exit 0
    fi
    # Pruning asks which containers still use a revision image.
    if [[ "$*" == *"ancestor=stroy-api:"* && -n "${FAKE_IMAGE_IN_USE:-}" && "$*" == *"ancestor=stroy-api:$FAKE_IMAGE_IN_USE"* ]]; then
      printf '%s\n' fake-user-container
    fi
    exit 0
    ;;
  inspect)
    if [[ -n "$previous_image" && "${2:-}" == "--format" && "${4:-}" == "fake-api-container" ]]; then
      case "${3:-}" in
        '{{json .Config.Env}}') printf '%s\n' '[]' ;;
        '{{.Image}}') printf '%s\n' sha256:previous ;;
        *) echo "unexpected docker inspect format: $*" >&2; exit 98 ;;
      esac
      exit 0
    fi
    ;;
  rm)
    if [[ -n "$previous_image" && "$*" == "rm --force fake-api-container" ]]; then
      printf '%s\n' "$*" >> "$DOCKER_LOG"
      exit 0
    fi
    ;;
  load)
    exit 0
    ;;
  image)
    if [[ "${2:-}" == "inspect" && "${3:-}" == "--format" ]]; then
      if [[ "${4:-}" == '{{.Id}}' ]]; then
        printf '%s\n' sha256:previous
      else
        printf '%s\n' "$VALID_SHA"
      fi
      exit 0
    fi
    if [[ "${2:-}" == "inspect" && "$#" == 3 ]]; then
      exit 0
    fi
    if [[ "${2:-}" == "rm" ]]; then
      printf '%s\n' "$*" >> "$DOCKER_LOG"
      exit 0
    fi
    ;;
  compose)
    if [[ "${API_IMAGE:-}" != "stroy-api:$VALID_SHA" && ( -z "$previous_image" || "${API_IMAGE:-}" != "$previous_image" ) ]]; then
      echo "compose received an unexpected API image" >&2
      exit 98
    fi
    if [[ "$*" == *" config --format json"* ]]; then
      printf '%s\n' '{"services":{"api":{"environment":{}}}}'
      exit 0
    fi
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    exit 0
    ;;
esac

echo "unexpected docker invocation: $*" >&2
exit 98
DOCKER
chmod +x "$temporary_dir/bin/docker"
cat > "$temporary_dir/bin/sudo" <<'SUDO'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo %s
' "$*" >> "${DOCKER_LOG:-/dev/null}"
if [[ "$*" != "-n /usr/bin/systemctl start --wait onlineprorab-backup.service" ]]; then
  echo "unexpected sudo invocation: $*" >&2
  exit 97
fi
exit "${FAKE_BACKUP_EXIT:-0}"
SUDO
chmod +x "$temporary_dir/bin/sudo"
cat > "$temporary_dir/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "show --property=Result --value onlineprorab-backup.service")
    printf '%s
' "${FAKE_BACKUP_RESULT:-success}"
    ;;
  "show --property=ConditionResult --value onlineprorab-backup.service")
    printf '%s
' "${FAKE_BACKUP_CONDITION:-yes}"
    ;;
  *)
    echo "unexpected systemctl invocation: $*" >&2
    exit 97
    ;;
esac
SYSTEMCTL
chmod +x "$temporary_dir/bin/systemctl"
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
stage_artifacts() {
  printf '%s' fake-image | gzip -c > "$image_archive"
  printf '%s\n' 'services: {}' > "$compose_file"
  printf '%s\n' '{"project_id":"stroy-notifications"}' > "$fcm_secret_file"
  cp "$script_dir/scripts/backup.sh" "$backup_script"
  cp "$script_dir/scripts/safe-path.sh" "$safe_path_script"
}
docker_log="$temporary_dir/docker.log"

expect_backup_gate() {
  local label="$1" expected_message="$2"
  shift 2
  local root="$temporary_dir/backup-gate-$label"
  local log="$temporary_dir/backup-gate-$label.log"
  local output="$temporary_dir/backup-gate-$label.out"
  stage_artifacts
  mkdir -p "$root"
  : > "$root/.env"
  chmod 600 "$root/.env"
  if env FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$log" "$@" \
    bash "$deploy_script" deploy "$valid_sha" "$root" api-production >"$output" 2>&1; then
    echo "deployment continued after a $label pre-deployment backup" >&2
    exit 1
  fi
  if ! grep -Fq "$expected_message" "$output"; then
    cat "$output" >&2
    echo "backup gate rejection did not explain the $label case" >&2
    exit 1
  fi
  if grep -Fq 'up --detach' "$log"; then
    echo "API release started even though the $label backup gate failed" >&2
    exit 1
  fi
  if [[ -e "$root/current" ]]; then
    echo "release pointer moved even though the $label backup gate failed" >&2
    exit 1
  fi
}
expect_backup_gate failed "pre-deployment backup failed" FAKE_BACKUP_EXIT=1
expect_backup_gate skipped "pre-deployment backup did not complete" FAKE_BACKUP_CONDITION=no
expect_backup_gate unsuccessful "pre-deployment backup did not complete" FAKE_BACKUP_RESULT=exit-code
stage_artifacts
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
backup_line="$(grep -n 'sudo -n /usr/bin/systemctl start --wait onlineprorab-backup.service' "$docker_log" | head -n 1 | cut -d: -f1)"
up_line="$(grep -n 'up --detach' "$docker_log" | head -n 1 | cut -d: -f1)"
if [[ -z "$backup_line" || "$backup_line" -ge "$up_line" ]]; then
  echo "successful deployment did not back up the database before starting the release" >&2
  exit 1
fi
for artifact in "$image_archive" "$compose_file" "$fcm_secret_file" "$backup_script" "$safe_path_script"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    echo "deployment left a transferred artifact behind: $artifact" >&2
    exit 1
  fi
done

if grep -Fq 'image rm' "$docker_log"; then
  echo "first deployment unexpectedly removed images" >&2
  exit 1
fi

# Release pruning: keep the new release, the release it rolls back to (even if
# it is the oldest), the baseline and the five most recent revisions.  Older
# revisions are removed, and their images only when no container uses them.
prune_root="$temporary_dir/prune-api"
prune_log="$temporary_dir/prune.log"
mkdir -p "$prune_root/releases"
: > "$prune_root/.env"
chmod 600 "$prune_root/.env"
make_release() {
  local name="$1" age_minutes="$2" previous="$3"
  local dir="$prune_root/releases/$name"
  mkdir -p "$dir/backend"
  printf '%s\n' 'services: {}' > "$dir/backend/docker-compose.prod.yml"
  if [[ "$name" == baseline ]]; then
    printf '%s\n' stroy-api:baseline > "$dir/image-tag"
  else
    printf 'stroy-api:%s\n' "$name" > "$dir/image-tag"
  fi
  printf '%s\n' "$previous" > "$dir/previous-release"
  touch -d "-$age_minutes minutes" "$dir"
}
fake_sha() {
  printf '%040x' "$1"
}
active_sha="$(fake_sha 100)"
make_release baseline 1000 ''
make_release "$active_sha" 900 releases/baseline
old_shas=()
for index in 1 2 3 4 5 6 7; do
  old_shas+=("$(fake_sha "$index")")
  # index 1 is the oldest, index 7 the most recent of the old revisions.
  make_release "$(fake_sha "$index")" $((800 - index * 10)) "releases/$(fake_sha $((index - 1)))"
done
ln -s "releases/$active_sha" "$prune_root/current"
stage_artifacts
if ! FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$prune_log" \
  FAKE_PREVIOUS_IMAGE="stroy-api:$active_sha" FAKE_IMAGE_IN_USE="${old_shas[1]}" \
  bash "$deploy_script" deploy "$valid_sha" "$prune_root" api-production; then
  echo "expected the pruning deployment fixture to succeed" >&2
  exit 1
fi
if [[ "$(readlink -- "$prune_root/current")" != "releases/$valid_sha" ]]; then
  echo "pruning deployment did not activate its managed release" >&2
  exit 1
fi
if [[ "$(cat "$prune_root/releases/$valid_sha/previous-release")" != "releases/$active_sha" ]]; then
  echo "pruning deployment recorded the wrong previous release" >&2
  exit 1
fi
expected_kept=("$valid_sha" "$active_sha" baseline "${old_shas[3]}" "${old_shas[4]}" "${old_shas[5]}" "${old_shas[6]}")
for kept in "${expected_kept[@]}"; do
  if [[ ! -d "$prune_root/releases/$kept" ]]; then
    echo "pruning removed a release that must be retained: $kept" >&2
    exit 1
  fi
done
for pruned in "${old_shas[0]}" "${old_shas[1]}" "${old_shas[2]}"; do
  if [[ -e "$prune_root/releases/$pruned" ]]; then
    echo "pruning kept an expired release: $pruned" >&2
    exit 1
  fi
done
if [[ "$(find "$prune_root/releases" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" != "${#expected_kept[@]}" ]]; then
  echo "pruning left an unexpected number of releases" >&2
  exit 1
fi
for removed in "${old_shas[0]}" "${old_shas[2]}"; do
  if ! grep -Fxq "image rm stroy-api:$removed" "$prune_log"; then
    echo "pruning did not remove the unused image of $removed" >&2
    exit 1
  fi
done
if grep -Fq "image rm stroy-api:${old_shas[1]}" "$prune_log"; then
  echo "pruning removed an image that a container still uses" >&2
  exit 1
fi
for kept in "${expected_kept[@]}"; do
  if grep -Fq "image rm stroy-api:$kept" "$prune_log"; then
    echo "pruning removed the image of a retained release: $kept" >&2
    exit 1
  fi
done
if [[ "$(grep -c 'image rm' "$prune_log")" != 2 ]]; then
  echo "pruning removed an unexpected number of images" >&2
  exit 1
fi

# Re-deploying the active revision (credential rotation) recreates the API but
# keeps the release history, and a recovery request afterwards must recreate the
# same release instead of downgrading to previous-release.
refresh_log="$temporary_dir/refresh.log"
stage_artifacts
printf '%s\n' '{"project_id":"stroy-notifications","private_key_id":"rotated"}' > "$fcm_secret_file"
if ! FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$refresh_log" \
  FAKE_PREVIOUS_IMAGE="stroy-api:$valid_sha" \
  bash "$deploy_script" deploy "$valid_sha" "$prune_root" api-production; then
  echo "re-deploying the active revision must refresh it, not fail" >&2
  exit 1
fi
if [[ "$(readlink -- "$prune_root/current")" != "releases/$valid_sha" ]]; then
  echo "refresh moved the release pointer" >&2
  exit 1
fi
if [[ "$(cat "$prune_root/releases/$valid_sha/previous-release")" != "releases/$active_sha" ]]; then
  echo "refresh overwrote the recorded previous release" >&2
  exit 1
fi
if [[ "$(cat "$prune_root/releases/$valid_sha/last-attempt")" != "refresh" ]]; then
  echo "refresh did not record its attempt kind" >&2
  exit 1
fi
if [[ ! -d "$prune_root/releases/$active_sha" ]]; then
  echo "refresh pruned the release it would roll back to" >&2
  exit 1
fi
if ! grep -Fq 'rm --force fake-api-container' "$refresh_log" || \
  ! grep -Fq 'up --detach --no-build --pull never --wait --wait-timeout 180 api' "$refresh_log"; then
  echo "refresh did not recreate the API container" >&2
  exit 1
fi
if ! grep -Fq '"private_key_id":"rotated"' "$prune_root/.fcm_service_account.json"; then
  echo "refresh did not install the rotated FCM credential" >&2
  exit 1
fi
recover_log="$temporary_dir/refresh-recover.log"
if ! FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$recover_log" \
  FAKE_PREVIOUS_IMAGE="stroy-api:$valid_sha" \
  bash "$deploy_script" rollback "$valid_sha" "$prune_root" api-production >"$temporary_dir/refresh-recover.out" 2>&1; then
  cat "$temporary_dir/refresh-recover.out" >&2
  echo "recovery after a refresh failed" >&2
  exit 1
fi
if [[ "$(readlink -- "$prune_root/current")" != "releases/$valid_sha" ]]; then
  echo "recovery after a refresh downgraded the active release" >&2
  exit 1
fi
if ! grep -Fq 'up --detach' "$recover_log"; then
  echo "recovery after a refresh did not recreate the active release" >&2
  exit 1
fi

# A transferred FCM credential that is not owned by the deploy user must be
# refused before it is installed (only checkable when running as root).
if [[ "$(id -u)" == 0 ]] && id nobody >/dev/null 2>&1; then
  fcm_root="$temporary_dir/fcm-owner-api"
  mkdir -p "$fcm_root"
  : > "$fcm_root/.env"
  chmod 600 "$fcm_root/.env"
  stage_artifacts
  chown nobody "$fcm_secret_file"
  if FAKE_DOCKER_MODE=deploy VALID_SHA="$valid_sha" DOCKER_LOG="$temporary_dir/fcm-owner.log" \
    bash "$deploy_script" deploy "$valid_sha" "$fcm_root" api-production >"$temporary_dir/fcm-owner.out" 2>&1; then
    echo "deployment accepted an FCM credential owned by another user" >&2
    exit 1
  fi
  if ! grep -Fq "transferred FCM credential must be owned by the deploy user" "$temporary_dir/fcm-owner.out"; then
    cat "$temporary_dir/fcm-owner.out" >&2
    exit 1
  fi
  if [[ -e "$fcm_root/.fcm_service_account.json" ]]; then
    echo "foreign FCM credential was installed" >&2
    exit 1
  fi
  rm -f -- "$image_archive" "$compose_file" "$fcm_secret_file" "$backup_script" "$safe_path_script"
fi
if [[ "$(stat -c '%a' "$successful_root/.fcm_service_account.json")" != "600" ]]; then
  echo "installed FCM credential is not private" >&2
  exit 1
fi

echo "Backend deployment guards, release installation and pruning passed."
