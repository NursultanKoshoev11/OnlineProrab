#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
deploy_script="$script_dir/deploy-remote.sh"
temporary_dir="$(mktemp -d)"
trap 'rm -rf -- "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin"
cat > "$temporary_dir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
echo "docker must not be called for rejected deployment input" >&2
exit 99
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
  if "$deploy_script" "$@" >"$output" 2>&1; then
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

echo "Backend deployment input guards passed."