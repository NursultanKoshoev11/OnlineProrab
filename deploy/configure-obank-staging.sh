#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ! -f .env ]]; then
  echo "Staging .env was not found; refusing to change any environment." >&2
  exit 1
fi

read -r -s -p "Sandbox merchant SID: " sid
printf '\n'
read -r -s -p "Sandbox API password: " password
printf '\n'
if [[ -z "$sid" || -z "$password" ]]; then
  echo "SID and password are required." >&2
  exit 1
fi

OBANK_SID="$sid" OBANK_PASSWORD="$password" python3 - <<'PY'
import os
import tempfile
from pathlib import Path

path = Path(".env")
updates = {
    "OBANK_ENABLED": "true",
    "OBANK_SID": os.environ["OBANK_SID"],
    "OBANK_PASSWORD": os.environ["OBANK_PASSWORD"],
    "OBANK_API_URL": "https://mw-api-test.dengi.kg/api/json/json.php",
    "OBANK_API_VERSION": "1005",
    "OBANK_TEST": "true",
    "OBANK_RESULT_URL": "https://stroy.com.kg/staging-api/api/v1/payments/obank/result",
    "OBANK_RETURN_URL": "https://stroy.com.kg/billing/",
}

def quote(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError("merchant credentials must be single-line values")
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

lines = path.read_text(encoding="utf-8").splitlines()
written = set()
updated_lines = []
for line in lines:
    key = line.partition("=")[0]
    if key in updates:
        if key not in written:
            updated_lines.append(key + "=" + quote(updates[key]))
            written.add(key)
    else:
        updated_lines.append(line)
for key, value in updates.items():
    if key not in written:
        updated_lines.append(key + "=" + quote(value))

fd, temp_name = tempfile.mkstemp(prefix=".env.obank.", dir=".")
try:
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(updated_lines) + "\n")
    os.replace(temp_name, path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)
os.chmod(path, 0o600)
PY

unset sid password

compose=(docker compose -p onlineprorab-staging -f docker-compose.staging.yml --env-file .env)
"${compose[@]}" config --quiet
"${compose[@]}" up -d --force-recreate api

healthy=false
for _ in $(seq 1 45); do
  status=$(docker inspect stroy-obank-staging-api --format '{{.State.Health.Status}}' 2>/dev/null || true)
  if [[ "$status" == "healthy" ]]; then
    healthy=true
    break
  fi
  sleep 2
done

if [[ "$healthy" != true ]] || ! docker exec stroy-obank-staging-api sh -c 'test "$OBANK_ENABLED" = true && test "$OBANK_TEST" = true && test -n "$OBANK_SID" && test -n "$OBANK_PASSWORD"'; then
  echo "Staging O!Bank configuration did not become healthy; production was not changed." >&2
  exit 1
fi

echo "Sandbox O!Bank is enabled in staging; credentials remain hidden."
