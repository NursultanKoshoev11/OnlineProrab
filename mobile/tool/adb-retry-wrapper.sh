#!/usr/bin/env bash
set -u

real_adb="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}/platform-tools/adb"
if [ ! -x "$real_adb" ]; then
  real_adb="/usr/local/lib/android/sdk/platform-tools/adb"
fi

# android-emulator-runner sends this unlock event immediately after it sees
# sys.boot_completed=1.  On software-rendered GitHub-hosted emulators the
# input service can still be restarting, which otherwise aborts the action with
# a broken-pipe error.  Retry only this known transient command; all other ADB
# commands retain their normal failure behavior.
if [[ " $* " == *" shell input keyevent 82 "* ]]; then
  for attempt in $(seq 1 30); do
    if "$real_adb" "$@"; then
      exit 0
    fi
    echo "ADB input service is not ready (attempt $attempt/30); retrying in 2s" >&2
    sleep 2
  done
  exit 1
fi

exec "$real_adb" "$@"
