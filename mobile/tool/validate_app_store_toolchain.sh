#!/usr/bin/env bash
set -euo pipefail

xcode_version="$(xcodebuild -version | awk '/^Xcode / {print $2}')"
ios_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
xcode_major="${xcode_version%%.*}"
ios_sdk_major="${ios_sdk_version%%.*}"

if [[ ! "$xcode_major" =~ ^[0-9]+$ || ! "$ios_sdk_major" =~ ^[0-9]+$ ]]; then
  echo "Could not determine Xcode and iOS SDK major versions." >&2
  exit 1
fi

if (( xcode_major < 26 || ios_sdk_major < 26 )); then
  echo "App Store Connect uploads require Xcode 26+ and the iOS 26+ SDK." >&2
  echo "Detected Xcode $xcode_version and iOS SDK $ios_sdk_version." >&2
  exit 1
fi

echo "App Store Connect SDK requirement satisfied: Xcode $xcode_version, iOS SDK $ios_sdk_version."
