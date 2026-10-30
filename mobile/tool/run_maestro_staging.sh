#!/usr/bin/env bash
set -euo pipefail

apk_path="mobile/build/app/outputs/flutter-apk/app-debug.apk"
installed=0

for attempt in 1 2 3 4 5 6; do
  if adb shell cmd package list packages >/dev/null 2>&1 && \
     adb install -r "$apk_path"; then
    installed=1
    break
  fi

  echo "Android package manager not ready (attempt $attempt/6); retrying in 10s"
  sleep 10
done

test "$installed" -eq 1
maestro test \
  --format junit \
  --output "$RUNNER_TEMP/maestro-results.xml" \
  mobile/.maestro/staging-login.yaml
