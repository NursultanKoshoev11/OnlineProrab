#!/usr/bin/env bash
# Prints a throwaway Firebase service-account JSON for the local E2E stack.
# The RSA key is generated on every run and only signs OAuth assertions sent
# to the fake token endpoint; it never leaves the runner.
set -euo pipefail
key="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)"
python_bin=python3
if ! python3 -c "" >/dev/null 2>&1; then python_bin=python; fi
"$python_bin" - "$key" <<'PY'
import json, sys
print(json.dumps({
    "type": "service_account",
    "project_id": "stroy-e2e",
    "private_key_id": "e2e-throwaway",
    "private_key": sys.argv[1] + "\n",
    "client_email": "e2e@stroy-e2e.iam.gserviceaccount.com",
    "client_id": "0",
    "token_uri": "http://fake-fcm:8090/token",
}, separators=(",", ":")))
PY
