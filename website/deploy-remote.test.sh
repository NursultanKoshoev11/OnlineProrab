#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deploy_script="$script_dir/deploy-remote.sh"
test_root="$(mktemp -d)"
mock_bin="$test_root/bin"
mock_log="$test_root/docker.log"
mkdir -m 700 "$mock_bin"
export MOCK_DOCKER_LOG="$mock_log"
export PATH="$mock_bin:$PATH"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

cat > "$mock_bin/docker" <<'MOCK_DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
case "${1:-}" in
  inspect)
    if [[ "${2:-}" == --format ]]; then
      printf '%s\n' 'sha256:previous-image'
      exit 0
    fi
    [[ "${MOCK_EXISTING_CONTAINER:-0}" == 1 ]]
    ;;
  load)
    exit 0
    ;;
  image)
    [[ "${2:-}" == tag ]]
    exit 0
    ;;
  compose)
    calls_file="${MOCK_COMPOSE_CALLS_FILE:?}"
    calls=0
    [[ ! -f "$calls_file" ]] || read -r calls < "$calls_file"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [[ "${MOCK_FAIL_FIRST_COMPOSE:-0}" == 1 && "$calls" == 1 ]]; then
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "Unexpected mocked Docker command: $*" >&2
    exit 99
    ;;
esac
MOCK_DOCKER
chmod 700 "$mock_bin/docker"

new_sha() {
  printf '%s-%s-%s' "$$" "$RANDOM" "$(date +%s%N)" | sha256sum | cut -c1-40
}

create_image_archive() {
  local sha="$1"
  : > "/tmp/stroy-website-${sha}.image.tar.gz"
}

create_regular_source_archive() {
  local sha="$1"
  local source_root="$test_root/source-$sha"
  mkdir -p "$source_root/website"
  printf '%s\n' 'services: {}' > "$source_root/website/docker-compose.yml"
  tar -czf "/tmp/stroy-website-${sha}.source.tar.gz" \
    -C "$source_root" website/docker-compose.yml
}

assert_rejected() {
  local sha="$1"
  local root="$2"
  if bash "$deploy_script" "$sha" "$root" >/dev/null 2>&1; then
    echo "Expected deploy to reject $root" >&2
    exit 1
  fi
}

canonical_root="$test_root/canonical"
mkdir -m 700 "$canonical_root" "$canonical_root/child"
linked_root="$test_root/root-link"
ln -s "$canonical_root" "$linked_root"
: > "$mock_log"
assert_rejected "$(new_sha)" "$linked_root"
assert_rejected "$(new_sha)" "$linked_root/child"
[[ ! -s "$mock_log" ]]

external_release="$test_root/external-release"
mkdir -p "$external_release/website" "$canonical_root/releases"
printf '%s\n' 'services: {}' > "$external_release/website/docker-compose.yml"
ln -s "$external_release" "$canonical_root/current"
: > "$mock_log"
assert_rejected "$(new_sha)" "$canonical_root"
[[ ! -s "$mock_log" ]]
rm "$canonical_root/current"

mkdir "$canonical_root/current"
assert_rejected "$(new_sha)" "$canonical_root"
rmdir "$canonical_root/current"

sha="$(new_sha)"
create_image_archive "$sha"
malicious_root="$test_root/malicious-source"
mkdir -p "$malicious_root/website"
ln -s /etc/passwd "$malicious_root/website/docker-compose.yml"
tar -czf "/tmp/stroy-website-${sha}.source.tar.gz" \
  -C "$malicious_root" website/docker-compose.yml
: > "$mock_log"
assert_rejected "$sha" "$canonical_root"
if grep -q '^load ' "$mock_log" || grep -q '^compose ' "$mock_log"; then
  echo "Unsafe archive reached Docker" >&2
  exit 1
fi

sha="$(new_sha)"
create_image_archive "$sha"
create_regular_source_archive "$sha"
calls_file="$test_root/success-compose-calls"
MOCK_COMPOSE_CALLS_FILE="$calls_file" \
MOCK_EXISTING_CONTAINER=0 \
MOCK_FAIL_FIRST_COMPOSE=0 \
  bash "$deploy_script" "$sha" "$canonical_root" >/dev/null
[[ "$(readlink -f "$canonical_root/current")" == "$canonical_root/releases/$sha" ]]
[[ "$(cat "$calls_file")" == 1 ]]

rollback_root="$test_root/rollback"
baseline="$rollback_root/releases/baseline"
mkdir -p "$baseline/website"
printf '%s\n' 'services: {}' > "$baseline/website/docker-compose.yml"
ln -s "$baseline" "$rollback_root/current"
sha="$(new_sha)"
create_image_archive "$sha"
create_regular_source_archive "$sha"
calls_file="$test_root/rollback-compose-calls"
if MOCK_COMPOSE_CALLS_FILE="$calls_file" \
  MOCK_EXISTING_CONTAINER=1 \
  MOCK_FAIL_FIRST_COMPOSE=1 \
  bash "$deploy_script" "$sha" "$rollback_root" >/dev/null 2>&1; then
  echo "Expected health-check failure to fail the deployment" >&2
  exit 1
fi
[[ "$(readlink -f "$rollback_root/current")" == "$baseline" ]]
[[ "$(cat "$calls_file")" == 2 ]]
grep -q '^image tag sha256:previous-image stroy-website:production$' "$mock_log"

printf '%s\n' 'Remote deployment path, archive, and rollback checks passed'
