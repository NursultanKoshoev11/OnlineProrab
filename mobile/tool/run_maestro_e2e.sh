#!/usr/bin/env bash
set -euo pipefail

results="${RUNNER_TEMP:-/tmp}/maestro-results.xml"
cli_log="${RUNNER_TEMP:-/tmp}/maestro-cli.log"
startup_png="${RUNNER_TEMP:-/tmp}/maestro-startup.png"
failure_png="${RUNNER_TEMP:-/tmp}/maestro-failure.png"
ui_xml="${RUNNER_TEMP:-/tmp}/maestro-ui.xml"
logcat="${RUNNER_TEMP:-/tmp}/maestro-logcat.txt"
apk_path="mobile/build/app/outputs/flutter-apk/app-debug.apk"

installed=0
for attempt in 1 2 3 4 5 6; do
  if adb shell cmd package list packages >/dev/null 2>&1 && adb install -r "$apk_path"; then
    installed=1
    break
  fi
  echo "Android package manager is not ready (attempt $attempt/6); retrying in 10s"
  sleep 10
done
test "$installed" -eq 1

capture_diagnostics() {
  adb exec-out screencap -p >"$failure_png" 2>/dev/null || true
  adb shell uiautomator dump /sdcard/maestro-ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/maestro-ui.xml "$ui_xml" >/dev/null 2>&1 || true
  adb logcat -d >"$logcat" 2>/dev/null || true
}
trap capture_diagnostics EXIT

adb shell monkey -p kg.com.stroy.app 1 >/dev/null 2>&1 || true
sleep 15
adb exec-out screencap -p >"$startup_png" 2>/dev/null || true
adb shell am force-stop kg.com.stroy.app >/dev/null 2>&1 || true

export MAESTRO_DRIVER_STARTUP_TIMEOUT="300000"
timeout --signal=TERM --kill-after=30s 900s maestro test \
  --format junit \
  --output "$results" \
  mobile/.maestro/e2e/local-stack.yaml 2>&1 | tee "$cli_log"
