#!/usr/bin/env bash
# Random-input (monkey) testing of the debug APK against the local E2E stack.
#
# Each round signs in with a different phone (so SMS cooldowns never block the
# login), clears logcat, sends random taps, swipes and key events confined to
# the STROY package, and then scans logcat for crashes, ANRs and Flutter
# exceptions. Seeds are printed so any failure can be replayed exactly with
#   adb shell monkey -p kg.com.stroy.app -s <seed> ... <events>
set -uo pipefail

package="kg.com.stroy.app"
out="${RUNNER_TEMP:-/tmp}/monkey"
apk_path="mobile/build/app/outputs/flutter-apk/app-debug.apk"
events="${MONKEY_EVENTS:-1500}"
throttle_ms="${MONKEY_THROTTLE_MS:-150}"
base_seed="${MONKEY_SEED:-$(( ${GITHUB_RUN_NUMBER:-1} * 100 ))}"
# Seeded owner with data, seeded trial user, then two fresh accounts.
phones=("+996700000001" "+996700000002" "+996700000011" "+996700000012")
mkdir -p "$out"

installed=0
for attempt in 1 2 3 4 5 6; do
  if adb shell cmd package list packages >/dev/null 2>&1 && adb install -r "$apk_path"; then
    installed=1
    break
  fi
  echo "Android package manager is not ready (attempt $attempt/6); retrying in 10s"
  sleep 10
done
if [[ "$installed" -ne 1 ]]; then
  echo "::error title=Monkey setup::could not install the debug APK"
  exit 1
fi

export MAESTRO_DRIVER_STARTUP_TIMEOUT="300000"
problems=0
round=0
for phone in "${phones[@]}"; do
  round=$((round + 1))
  seed=$((base_seed + round))
  prefix="$out/round-$round"
  echo "::group::Monkey round $round (seed $seed, $events events)"

  if ! timeout --signal=TERM --kill-after=30s 600s maestro test \
      -e PHONE="$phone" mobile/.maestro/e2e/login.yaml >"$prefix-login.log" 2>&1; then
    echo "::error title=Monkey round $round::login before random input failed; see $prefix-login.log"
    adb exec-out screencap -p >"$prefix-login-failure.png" 2>/dev/null || true
    problems=$((problems + 1))
    echo "::endgroup::"
    continue
  fi

  adb logcat -c || true
  timeout --signal=TERM --kill-after=30s 900s adb shell monkey \
    -p "$package" -s "$seed" --throttle "$throttle_ms" \
    --pct-syskeys 0 --pct-appswitch 0 --pct-anyevent 0 \
    --ignore-crashes --ignore-timeouts --ignore-security-exceptions \
    -v "$events" >"$prefix-monkey.txt" 2>&1
  echo "monkey exit code: $?" >>"$prefix-monkey.txt"
  adb exec-out screencap -p >"$prefix-end.png" 2>/dev/null || true
  adb logcat -d >"$prefix-logcat.txt" 2>/dev/null || true

  # Signals of a real defect. Each is counted separately so the summary says
  # what kind of problem the round hit.
  crashes=$(grep -c -E "FATAL EXCEPTION|// CRASH: $package" "$prefix-monkey.txt" "$prefix-logcat.txt" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
  anrs=$(grep -c -E "ANR in $package|// NOT RESPONDING: $package" "$prefix-monkey.txt" "$prefix-logcat.txt" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
  unhandled=$(grep -c -E "E/flutter.*Unhandled Exception" "$prefix-logcat.txt" 2>/dev/null || true)
  framework=$(grep -c -E "EXCEPTION CAUGHT BY" "$prefix-logcat.txt" 2>/dev/null || true)
  unhandled=${unhandled:-0}
  framework=${framework:-0}
  echo "round=$round seed=$seed phone_index=$round crashes=$crashes anrs=$anrs unhandled_dart=$unhandled flutter_framework=$framework" | tee -a "$out/summary.txt"
  if (( crashes + anrs + unhandled + framework > 0 )); then
    problems=$((problems + 1))
    echo "::error title=Monkey round $round (seed $seed)::crashes=$crashes ANRs=$anrs unhandled Dart exceptions=$unhandled Flutter framework exceptions=$framework"
    grep -E -A 12 "FATAL EXCEPTION|ANR in $package|Unhandled Exception|EXCEPTION CAUGHT BY" "$prefix-logcat.txt" >"$prefix-excerpt.txt" 2>/dev/null || true
  fi
  echo "::endgroup::"
done

echo "Monkey summary:"
cat "$out/summary.txt" 2>/dev/null || true
if (( problems > 0 )); then
  echo "::error title=Monkey testing::$problems of ${#phones[@]} rounds found problems"
  exit 1
fi
