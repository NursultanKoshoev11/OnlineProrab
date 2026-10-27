#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
UPLOAD_DIR="${UPLOAD_DIR:-/data/uploads}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/onlineprorab}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
STORAGE_DRIVER="${STORAGE_DRIVER:-local}"
APP_ENV="${APP_ENV:-development}"
S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-}"
BACKUP_AGE_RECIPIENTS_FILE="${BACKUP_AGE_RECIPIENTS_FILE:-}"
BACKUP_METRIC_NAMESPACE="${BACKUP_METRIC_NAMESPACE:-}"

case "$APP_ENV" in
  staging|production)
    if [ "$STORAGE_DRIVER" != "s3" ]; then
      echo "STORAGE_DRIVER=s3 is required for staging and production backups" >&2
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
    : "${S3_BACKUP_BUCKET:?S3_BACKUP_BUCKET is required when STORAGE_DRIVER=s3}"
    if [ "$S3_BUCKET" = "$S3_BACKUP_BUCKET" ] || \
      [ "$S3_BUCKET" = "$S3_DELETION_LEDGER_BUCKET" ] || \
      [ "$S3_BACKUP_BUCKET" = "$S3_DELETION_LEDGER_BUCKET" ]; then
      echo "S3_BUCKET, S3_DELETION_LEDGER_BUCKET, and S3_BACKUP_BUCKET must be different" >&2
      exit 2
    fi
    : "${BACKUP_AGE_RECIPIENTS_FILE:?BACKUP_AGE_RECIPIENTS_FILE is required when STORAGE_DRIVER=s3}"
    case "$APP_ENV" in
      staging|production)
        : "${BACKUP_METRIC_NAMESPACE:?BACKUP_METRIC_NAMESPACE is required for monitored S3 backups}"
        ;;
    esac
    command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required when STORAGE_DRIVER=s3" >&2; exit 127; }
    command -v age >/dev/null 2>&1 || { echo "age is required for encrypted S3 backups" >&2; exit 127; }
    if [ ! -f "$BACKUP_AGE_RECIPIENTS_FILE" ] || [ -L "$BACKUP_AGE_RECIPIENTS_FILE" ]; then
      echo "BACKUP_AGE_RECIPIENTS_FILE must be a regular, non-symlink file" >&2
      exit 2
    fi
    ;;
  *) echo "STORAGE_DRIVER must be local or s3" >&2; exit 2 ;;
esac

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
. "$script_dir/safe-path.sh"
UPLOAD_DIR="$(safe_directory_path "$UPLOAD_DIR" UPLOAD_DIR)"
BACKUP_DIR="$(safe_directory_path "$BACKUP_DIR" BACKUP_DIR)"
case "$BACKUP_DIR/" in
  "$UPLOAD_DIR/"* ) echo "BACKUP_DIR and UPLOAD_DIR must be separate directories" >&2; exit 2 ;;
esac
case "$UPLOAD_DIR/" in
  "$BACKUP_DIR/"* ) echo "BACKUP_DIR and UPLOAD_DIR must be separate directories" >&2; exit 2 ;;
esac

case "$RETENTION_DAYS" in
  ''|*[!0-9]*) echo "RETENTION_DAYS must be a non-negative integer" >&2; exit 2 ;;
esac

command -v pg_dump >/dev/null 2>&1 || { echo "pg_dump is required" >&2; exit 127; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 127; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 127; }

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
final_dir="$BACKUP_DIR/$timestamp"
tmp_dir="$BACKUP_DIR/.${timestamp}.tmp.$$"
if [ -e "$final_dir" ] || [ -L "$final_dir" ]; then
  echo "backup already exists for this timestamp" >&2
  exit 2
fi

cleanup() {
  if [ "${tmp_created:-0}" -eq 1 ]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

umask 077
mkdir -m 700 "$tmp_dir"
tmp_created=1

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$tmp_dir/database.dump" \
  "$DATABASE_URL"

case "$STORAGE_DRIVER" in
  local)
    if [ -d "$UPLOAD_DIR" ]; then
      if find "$UPLOAD_DIR" ! -type d ! -type f -print -quit | grep -q .; then
        echo "UPLOAD_DIR may contain only regular files and directories" >&2
        exit 2
      fi
      tar -C "$UPLOAD_DIR" -czf "$tmp_dir/uploads.tar.gz" .
    else
      empty_dir="$tmp_dir/empty-uploads"
      mkdir -p "$empty_dir"
      tar -C "$empty_dir" -czf "$tmp_dir/uploads.tar.gz" .
      rmdir "$empty_dir"
    fi
    (
      cd "$tmp_dir"
      sha256sum database.dump uploads.tar.gz > SHA256SUMS
    )
    cat > "$tmp_dir/MANIFEST" <<EOF
created_at_utc=$timestamp
format_version=1
postgres_format=custom
uploads_format=tar.gz
EOF
    ;;
  s3)
    s3_stage="$tmp_dir/s3-uploads"
    mkdir -m 700 "$s3_stage"
    aws --region "$S3_REGION" s3 sync "s3://$S3_BUCKET" "$s3_stage" --only-show-errors
    if find "$s3_stage" ! -type d ! -type f -print -quit | grep -q .; then
      echo "S3 download may contain only regular files and directories" >&2
      exit 2
    fi
    tar -C "$s3_stage" -czf "$tmp_dir/uploads.tar.gz" .
    rm -rf "$s3_stage"
    (
      cd "$tmp_dir"
      sha256sum database.dump uploads.tar.gz > SHA256SUMS
      tar -cf snapshot.tar database.dump uploads.tar.gz SHA256SUMS
    )
    age --encrypt --recipients-file "$BACKUP_AGE_RECIPIENTS_FILE" \
      --output "$tmp_dir/snapshot.tar.age" "$tmp_dir/snapshot.tar"
    rm -f "$tmp_dir/database.dump" "$tmp_dir/uploads.tar.gz" "$tmp_dir/SHA256SUMS" "$tmp_dir/snapshot.tar"
    cat > "$tmp_dir/MANIFEST" <<EOF
created_at_utc=$timestamp
format_version=2
snapshot_format=tar
encryption=age
EOF
    ;;
esac

chmod -R go-rwx "$tmp_dir"
mv "$tmp_dir" "$final_dir"
trap - EXIT HUP INT TERM

backup_reference="$final_dir"
if [ "$STORAGE_DRIVER" = "s3" ]; then
  archive_host="$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9-')"
  [ -n "$archive_host" ] || archive_host=unknown
  archive_id="$timestamp-$archive_host-$$"
  archive_prefix="s3://$S3_BACKUP_BUCKET/snapshots/$archive_id"
  aws --region "$S3_REGION" s3 cp "$final_dir/snapshot.tar.age" \
    "$archive_prefix/snapshot.tar.age" --only-show-errors
  aws --region "$S3_REGION" s3 cp "$final_dir/MANIFEST" \
    "$archive_prefix/MANIFEST" --only-show-errors
  case "$APP_ENV" in
    staging|production)
      backup_metric_data="$(printf '{"MetricName":"BackupSucceeded","Dimensions":[{"Name":"Environment","Value":"%s"}],"Value":1,"Unit":"Count"}' "$APP_ENV")"
      aws --region "$S3_REGION" cloudwatch put-metric-data \
        --namespace "$BACKUP_METRIC_NAMESPACE" \
        --metric-data "$backup_metric_data"
      ;;
  esac
  backup_reference="$archive_prefix/"
fi

for snapshot_dir in "$BACKUP_DIR"/*; do
  [ -d "$snapshot_dir" ] || continue
  [ ! -L "$snapshot_dir" ] || continue
  snapshot_name="${snapshot_dir##*/}"
  case "$snapshot_name" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
    *) continue ;;
  esac
  find "$snapshot_dir" -maxdepth 0 -mtime "+$RETENTION_DAYS" -exec rm -rf {} \;
done

printf '%s\n' "$backup_reference"
