#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${CONFIRM_RESTORE:?Set CONFIRM_RESTORE=YES to allow destructive restore}"

if [ "$CONFIRM_RESTORE" != "YES" ]; then
  echo "CONFIRM_RESTORE must equal YES" >&2
  exit 2
fi

backup_dir="${1:-}"
if [ -z "$backup_dir" ]; then
  echo "usage: restore.sh /path/to/backup-directory" >&2
  exit 2
fi
backup_dir="$(cd "$backup_dir" && pwd)"
UPLOAD_DIR="${UPLOAD_DIR:-/data/uploads}"

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

staging_parent="$(dirname "$UPLOAD_DIR")"
staging_dir="$staging_parent/.onlineprorab-restore.$$"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$staging_dir"
tar -C "$staging_dir" -xzf "$backup_dir/uploads.tar.gz"

pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  --dbname="$DATABASE_URL" \
  "$backup_dir/database.dump"

mkdir -p "$UPLOAD_DIR"
find "$UPLOAD_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$staging_dir"/. "$UPLOAD_DIR"/

trap - EXIT HUP INT TERM
rm -rf "$staging_dir"
echo "restore completed"
