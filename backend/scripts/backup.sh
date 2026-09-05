#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
UPLOAD_DIR="${UPLOAD_DIR:-/data/uploads}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/onlineprorab}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

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

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$tmp_dir"

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$tmp_dir/database.dump" \
  "$DATABASE_URL"

if [ -d "$UPLOAD_DIR" ]; then
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

find "$BACKUP_DIR" \
  -mindepth 1 -maxdepth 1 -type d \
  ! -name ".*" \
  -mtime "+$RETENTION_DAYS" \
  -exec rm -rf {} +

printf '%s\n' "$final_dir"
