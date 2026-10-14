#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${CONFIRM_RESTORE:?Set CONFIRM_RESTORE=YES to allow destructive restore}"

if [ "$CONFIRM_RESTORE" != "YES" ]; then
  echo "CONFIRM_RESTORE must equal YES" >&2
  exit 2
fi

STORAGE_DRIVER="${STORAGE_DRIVER:-local}"
case "$STORAGE_DRIVER" in
  local) ;;
  s3)
    : "${S3_REGION:?S3_REGION is required when STORAGE_DRIVER=s3}"
    : "${S3_BUCKET:?S3_BUCKET is required when STORAGE_DRIVER=s3}"
    : "${S3_DELETION_LEDGER_BUCKET:?S3_DELETION_LEDGER_BUCKET is required when STORAGE_DRIVER=s3}"
    if [ "$S3_BUCKET" = "$S3_DELETION_LEDGER_BUCKET" ]; then
      echo "S3_BUCKET and S3_DELETION_LEDGER_BUCKET must be different" >&2
      exit 2
    fi
    command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required when STORAGE_DRIVER=s3" >&2; exit 127; }
    command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required when STORAGE_DRIVER=s3" >&2; exit 127; }
    command -v psql >/dev/null 2>&1 || { echo "psql is required when STORAGE_DRIVER=s3" >&2; exit 127; }
    ;;
  *) echo "STORAGE_DRIVER must be local or s3" >&2; exit 2 ;;
esac

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$script_dir/safe-path.sh"
UPLOAD_DIR="$(safe_directory_path "${UPLOAD_DIR:-/data/uploads}" UPLOAD_DIR)"

backup_dir="${1:-}"
if [ -z "$backup_dir" ]; then
  echo "usage: restore.sh /path/to/backup-directory" >&2
  exit 2
fi
backup_dir="$(cd "$backup_dir" && pwd)"

command -v pg_restore >/dev/null 2>&1 || { echo "pg_restore is required" >&2; exit 127; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 127; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 127; }

for file in database.dump uploads.tar.gz SHA256SUMS MANIFEST; do
  if [ ! -f "$backup_dir/$file" ]; then
    echo "backup is incomplete: missing $file" >&2
    exit 3
  fi
done

(
  cd "$backup_dir"
  sha256sum -c SHA256SUMS
)

if tar -tzf "$backup_dir/uploads.tar.gz" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null 2>&1; then
  echo "uploads archive contains unsafe paths" >&2
  exit 4
fi
if tar -tvzf "$backup_dir/uploads.tar.gz" | awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { found = 1 } END { exit !found }'; then
  echo "uploads archive may contain only regular files and directories" >&2
  exit 4
fi

staging_parent="$(dirname "$UPLOAD_DIR")"
staging_dir="$staging_parent/.onlineprorab-restore.$$"
tombstone_stage="$staging_parent/.onlineprorab-tombstones.$$"
cleanup() {
  if [ "${staging_created:-0}" -eq 1 ]; then
    rm -rf "$staging_dir"
  fi
  if [ "${tombstone_stage_created:-0}" -eq 1 ]; then
    rm -rf "$tombstone_stage"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
umask 077
mkdir -m 700 "$staging_dir"
staging_created=1
tar -C "$staging_dir" --no-same-owner --no-same-permissions -xzf "$backup_dir/uploads.tar.gz"

if [ "$STORAGE_DRIVER" = "s3" ]; then
  mkdir -m 700 "$tombstone_stage"
  tombstone_stage_created=1
  aws --region "$S3_REGION" s3 sync "s3://$S3_DELETION_LEDGER_BUCKET/tombstones/" "$tombstone_stage" --only-show-errors
  python3 "$script_dir/apply-deletion-tombstones.py" \
    "$tombstone_stage" "$tombstone_stage/apply.sql" "$tombstone_stage/delete-objects"
fi

if [ -L "$UPLOAD_DIR" ]; then
  echo "UPLOAD_DIR must not be a symbolic link" >&2
  exit 2
fi
mkdir -p "$UPLOAD_DIR"
if [ -L "$UPLOAD_DIR" ]; then
  echo "UPLOAD_DIR must not be a symbolic link" >&2
  exit 2
fi

pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  --dbname="$DATABASE_URL" \
  "$backup_dir/database.dump"

case "$STORAGE_DRIVER" in
  local)
    find "$UPLOAD_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "$staging_dir"/. "$UPLOAD_DIR"/
    ;;
  s3)
    aws --region "$S3_REGION" s3 sync "$staging_dir" "s3://$S3_BUCKET" --delete --only-show-errors
    for delete_batch in "$tombstone_stage"/delete-objects/*.json; do
      if [ ! -f "$delete_batch" ]; then
        continue
      fi
      response_file="${delete_batch%.json}.response.json"
      aws --region "$S3_REGION" s3api delete-objects \
        --bucket "$S3_BUCKET" \
        --delete "file://$delete_batch" \
        --output json > "$response_file"
      python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response_file:
    response = json.load(response_file)
if response.get("Errors"):
    raise SystemExit(f"S3 reported failed tombstone object deletions: {response['Errors']}")
PY
    done
    psql --set=ON_ERROR_STOP=1 --dbname="$DATABASE_URL" --file="$tombstone_stage/apply.sql"
    ;;
esac

rm -rf "$staging_dir"
staging_created=0
tombstone_stage_created=0
trap - EXIT HUP INT TERM
echo "restore completed"
