#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${CONFIRM_RESTORE:?Set CONFIRM_RESTORE=YES to allow destructive restore}"

if [ "$CONFIRM_RESTORE" != "YES" ]; then
  echo "CONFIRM_RESTORE must equal YES" >&2
  exit 2
fi

STORAGE_DRIVER="${STORAGE_DRIVER:-local}"
APP_ENV="${APP_ENV:-development}"
case "$APP_ENV" in
  staging|production)
    if [ "$STORAGE_DRIVER" != "s3" ]; then
      echo "STORAGE_DRIVER=s3 is required for staging and production restores" >&2
      exit 2
    fi
    ;;
esac
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

if [ ! -f "$backup_dir/MANIFEST" ]; then
  echo "backup is incomplete: missing MANIFEST" >&2
  exit 3
fi

staging_parent="$(dirname "$UPLOAD_DIR")"
staging_dir="$staging_parent/.onlineprorab-restore.$$"
restore_data_dir="$staging_parent/.onlineprorab-restore-data.$$"
tombstone_stage="$staging_parent/.onlineprorab-tombstones.$$"
cleanup() {
  if [ "${staging_created:-0}" -eq 1 ]; then
    rm -rf "$staging_dir"
  fi
  if [ "${restore_data_created:-0}" -eq 1 ]; then
    rm -rf "$restore_data_dir"
  fi
  if [ "${tombstone_stage_created:-0}" -eq 1 ]; then
    rm -rf "$tombstone_stage"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
umask 077

manifest_format="$(awk -F= '$1 == "format_version" { print $2 }' "$backup_dir/MANIFEST")"
case "$manifest_format" in
  1)
    if [ "$STORAGE_DRIVER" = "s3" ] && [ "${ALLOW_UNENCRYPTED_RESTORE:-NO}" != "YES" ]; then
      echo "unencrypted S3 backup rejected; set ALLOW_UNENCRYPTED_RESTORE=YES only for an approved legacy restore" >&2
      exit 3
    fi
    for file in database.dump uploads.tar.gz SHA256SUMS; do
      if [ ! -f "$backup_dir/$file" ]; then
        echo "backup is incomplete: missing $file" >&2
        exit 3
      fi
    done
    restore_database_dump="$backup_dir/database.dump"
    restore_uploads_archive="$backup_dir/uploads.tar.gz"
    (
      cd "$backup_dir"
      sha256sum -c SHA256SUMS
    )
    ;;
  2)
    if ! grep -qx 'encryption=age' "$backup_dir/MANIFEST"; then
      echo "unsupported encrypted backup format" >&2
      exit 3
    fi
    if [ ! -f "$backup_dir/snapshot.tar.age" ] || [ -L "$backup_dir/snapshot.tar.age" ]; then
      echo "backup is incomplete or unsafe: snapshot.tar.age is missing" >&2
      exit 3
    fi
    : "${BACKUP_AGE_IDENTITY_FILE:?BACKUP_AGE_IDENTITY_FILE is required for encrypted backups}"
    if [ ! -f "$BACKUP_AGE_IDENTITY_FILE" ] || [ -L "$BACKUP_AGE_IDENTITY_FILE" ]; then
      echo "BACKUP_AGE_IDENTITY_FILE must be a regular, non-symlink file" >&2
      exit 2
    fi
    command -v age >/dev/null 2>&1 || { echo "age is required to restore encrypted backups" >&2; exit 127; }
    mkdir -m 700 "$restore_data_dir"
    restore_data_created=1
    age --decrypt --identity "$BACKUP_AGE_IDENTITY_FILE" \
      --output "$restore_data_dir/snapshot.tar" "$backup_dir/snapshot.tar.age"
    payload_files="$(tar -tf "$restore_data_dir/snapshot.tar" | LC_ALL=C sort)"
    expected_payload_files="$(printf 'SHA256SUMS\ndatabase.dump\nuploads.tar.gz')"
    if [ "$payload_files" != "$expected_payload_files" ]; then
      echo "encrypted backup payload has an unexpected file list" >&2
      exit 4
    fi
    if tar -tvf "$restore_data_dir/snapshot.tar" | awk 'substr($0, 1, 1) != "-" { found = 1 } END { exit !found }'; then
      echo "encrypted backup payload may contain only regular files" >&2
      exit 4
    fi
    tar -C "$restore_data_dir" --no-same-owner --no-same-permissions -xf "$restore_data_dir/snapshot.tar"
    for file in database.dump uploads.tar.gz SHA256SUMS; do
      if [ ! -f "$restore_data_dir/$file" ] || [ -L "$restore_data_dir/$file" ]; then
        echo "encrypted backup payload is incomplete or unsafe: $file" >&2
        exit 4
      fi
    done
    (
      cd "$restore_data_dir"
      sha256sum -c SHA256SUMS
    )
    restore_database_dump="$restore_data_dir/database.dump"
    restore_uploads_archive="$restore_data_dir/uploads.tar.gz"
    ;;
  *)
    echo "unsupported backup format version" >&2
    exit 3
    ;;
esac

if tar -tzf "$restore_uploads_archive" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null 2>&1; then
  echo "uploads archive contains unsafe paths" >&2
  exit 4
fi
if tar -tvzf "$restore_uploads_archive" | awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { found = 1 } END { exit !found }'; then
  echo "uploads archive may contain only regular files and directories" >&2
  exit 4
fi

mkdir -m 700 "$staging_dir"
staging_created=1
tar -C "$staging_dir" --no-same-owner --no-same-permissions -xzf "$restore_uploads_archive"

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
  "$restore_database_dump"

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
if [ "${restore_data_created:-0}" -eq 1 ]; then
  rm -rf "$restore_data_dir"
  restore_data_created=0
fi
if [ "${tombstone_stage_created:-0}" -eq 1 ]; then
  rm -rf "$tombstone_stage"
  tombstone_stage_created=0
fi
trap - EXIT HUP INT TERM
echo "restore completed"
