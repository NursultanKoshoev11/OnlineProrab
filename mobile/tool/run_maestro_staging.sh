#!/usr/bin/env bash
set -euo pipefail

apk_path="mobile/build/app/outputs/flutter-apk/app-profile.apk"
installed=0

capture_diagnostics() {
  if [ -z "${RUNNER_TEMP:-}" ]; then
    return
  fi

  adb exec-out screencap -p >"$RUNNER_TEMP/maestro-startup.png" 2>/dev/null || true
  adb shell uiautomator dump /sdcard/maestro-startup.xml >/dev/null 2>&1 || true
  adb pull /sdcard/maestro-startup.xml "$RUNNER_TEMP/maestro-startup.xml" >/dev/null 2>&1 || true
  adb shell dumpsys activity activities >"$RUNNER_TEMP/maestro-activity.txt" 2>/dev/null || true
  adb shell dumpsys window windows >"$RUNNER_TEMP/maestro-windows.txt" 2>/dev/null || true
  adb logcat -d -b all -t 5000 >"$RUNNER_TEMP/maestro-logcat.txt" 2>/dev/null || true
}

trap capture_diagnostics EXIT

# Hosted GitHub runners can expose the emulator before ADB and Android system
# services are actually usable.  Starting the app during that window can cause
# the Android system ANR dialog and leave Flutter on its splash screen.  Wait
# for a stable device before installing or launching the app.
device_ready=0
for attempt in $(seq 1 90); do
  state="$(adb get-state 2>/dev/null || true)"
  boot_completed="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  boot_animation="$(adb shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || true)"
  if [ "$state" = "device" ] && [ "$boot_completed" = "1" ] && \
     { [ -z "$boot_animation" ] || [ "$boot_animation" = "stopped" ]; } && \
     adb shell pm list packages >/dev/null 2>&1 && \
     adb shell sm list-volumes all 2>/dev/null | grep -q .; then
    device_ready=1
    break
  fi

  echo "Android device is not stable yet (attempt $attempt/90); retrying in 5s"
  sleep 5
done

test "$device_ready" -eq 1

# Give SystemUI and package services a short settling window after boot.  This
# is intentionally before app launch; it does not mask application failures.
sleep 20

package_services_ready=0
for attempt in $(seq 1 24); do
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
set +e
timeout --signal=TERM --kill-after=30s 1800s maestro test \
  --env "STAGING_TEST_PHONE=$STAGING_TEST_PHONE" \
  --env "STAGING_TEST_CODE=$STAGING_TEST_CODE" \
  --format junit \
  --output "$RUNNER_TEMP/maestro-results.xml" \
  mobile/.maestro/staging-regression.yaml
maestro_status=$?
set -e
exit "$maestro_status"
