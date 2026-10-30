#!/usr/bin/env bash
set -euo pipefail

apk_path="mobile/build/app/outputs/flutter-apk/app-debug.apk"
installed=0

package_services_ready=0
for attempt in $(seq 1 36); do
  if adb shell pm path android 2>/dev/null | grep -q '^package:' && \
     adb shell sm list-volumes all 2>/dev/null | grep -q .; then
    package_services_ready=1
    break
  fi

  echo "Android package/storage services not ready (attempt $attempt/36); retrying in 10s"
  sleep 10
done

test "$package_services_ready" -eq 1

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
# GitHub-hosted runners use a software-rendered emulator without KVM.  The
# Maestro Android driver can need several minutes to install, dex-opt, and
# start on that constrained path, so keep the timeout explicit and bounded.
export MAESTRO_DRIVER_STARTUP_TIMEOUT="300000"
timeout --signal=TERM --kill-after=30s 900s maestro test \
  --format junit \
  --output "$RUNNER_TEMP/maestro-results.xml" \
  mobile/.maestro/staging-login.yaml
