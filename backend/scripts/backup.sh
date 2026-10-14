#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
UPLOAD_DIR="${UPLOAD_DIR:-/data/uploads}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/onlineprorab}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

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

chmod -R go-rwx "$tmp_dir"
mv "$tmp_dir" "$final_dir"
trap - EXIT HUP INT TERM

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

printf '%s\n' "$final_dir"
