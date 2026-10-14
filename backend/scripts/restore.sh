#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${CONFIRM_RESTORE:?Set CONFIRM_RESTORE=YES to allow destructive restore}"

if [ "$CONFIRM_RESTORE" != "YES" ]; then
  echo "CONFIRM_RESTORE must equal YES" >&2
  exit 2
fi

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
cleanup() {
  if [ "${staging_created:-0}" -eq 1 ]; then
    rm -rf "$staging_dir"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
umask 077
mkdir -m 700 "$staging_dir"
staging_created=1
tar -C "$staging_dir" --no-same-owner --no-same-permissions -xzf "$backup_dir/uploads.tar.gz"

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

find "$UPLOAD_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a "$staging_dir"/. "$UPLOAD_DIR"/

rm -rf "$staging_dir"
staging_created=0
trap - EXIT HUP INT TERM
echo "restore completed"
