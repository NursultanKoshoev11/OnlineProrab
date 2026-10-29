# STROY mobile release

## Android

On each mobile change merged to `main`, `Mobile CI` builds online and offline
debug APK artifacts. Signed release builds run automatically only after the
production API storage cutover is complete. Configure the Android upload key
and application ID in the `production-mobile` GitHub Environment; until then,
the workflow reports the missing setup and keeps the debug APK artifacts.
Signed APK and AAB use the same monotonically increasing GitHub Actions build
number. The signed iOS IPA uses that same readiness gate and the existing Apple
signing secrets. The iOS simulator artifact continues to build for staging.

- Environment variable `STROY_APPLICATION_ID`: the exact Android package ID registered in
  Google Play.
- Environment secrets `STROY_KEYSTORE_BASE64`, `STROY_KEYSTORE_PASSWORD`,
  `STROY_KEY_ALIAS`, and `STROY_KEY_PASSWORD`: the Play upload keystore and
  credentials.
- Environment variable `GOOGLE_PLAY_PACKAGE_NAME`: the exact Android package
  registered in Google Play (currently `kg.com.stroy.app`).
- Environment secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`: the Google Cloud
  service-account JSON key authorized in Play Console to release testing
  versions.

The workflow validates the release inputs, runs analysis and tests, and saves
the signed APK and AAB as GitHub Actions artifacts, and uploads the AAB to the
Google Play `internal` track. It never publishes the working production track.
The production signing and closed-testing upload job runs automatically after
the API cutover and signing configuration are complete. Automatic pushes use
the `alpha` track. To publish a signed build to Google Play Production, run
`Mobile CI` manually from `main` with `production_release=true` and
`google_play_track=production`; this is intentionally explicit so a normal
code push cannot publish directly to Production by accident.

Since August 31, 2026, Google Play requires new apps and app updates to target
Android 16 (API 36) or higher. The Android Gradle configuration targets API 36,
and CI checks that it does not fall below this policy minimum.

## iOS

The iOS simulator build runs on pull requests and pushes. On mobile changes
merged to `main`, the workflow builds and signs an App Store IPA after the
production API cutover. `workflow_dispatch` remains available for manual IPA
builds. Configure the values below in `production-mobile`:

- Environment variable `STROY_IOS_BUNDLE_ID`: the exact App Store Connect bundle ID. It defaults to `com.koshoev.stroy` from the current App Store Connect app record.
- Environment variable `STROY_IOS_TEAM_ID`: the Apple Developer Team ID that owns that app.
- Environment secret `STROY_IOS_CERTIFICATE_BASE64`: base64-encoded Apple Distribution
  `.p12` certificate.
- Environment secret `STROY_IOS_CERTIFICATE_PASSWORD`: password for that `.p12` file.
- Environment secret `STROY_IOS_PROVISIONING_PROFILE_BASE64`: base64-encoded App Store
  provisioning profile for the same bundle ID and team.

The workflow CMS-decodes the profile before reading its plist, then checks its
expiration, team, bundle ID, and App Store distribution settings. It creates a
signed IPA and saves it as a GitHub Actions artifact; it does not upload the IPA
to App Store Connect. The iOS deployment target is 14.0 because the file picker
plugin requires iOS 14 or newer.

Apple requires uploads to App Store Connect to use Xcode 26 or later with the
iOS 26 SDK as of April 28, 2026. Both the iOS simulator CI job and the signed
IPA job run on the `macos-26` image and enforce these toolchain versions before
building. Apple has announced that submissions beginning in April 2027 must
target iOS 15 or later; review the deployment target before that deadline if
support for iOS 14 devices is needed.

## Release checks

- Update `version` in `pubspec.yaml` when the user-visible app version changes.
  CI assigns the monotonically increasing store build number from the GitHub
  Actions run number.
- Confirm the configured Android package ID and iOS bundle ID match their
  store records.
- Complete the app privacy details and provide the public privacy-policy and
  support URLs in each store listing.
- Use `https://stroy.com.kg/privacy/` as the public privacy-policy URL. For
  Google Play's external account-deletion URL, use
  `https://stroy.com.kg/account-deletion/`. The signed Android and iOS release
  jobs check that both pages return their expected public content before they
  create release artifacts.
- Disclose the app's account and project data, uploaded files, voice
  recognition, and external AI expense-search processing in each store's
  privacy forms. Voice audio is sent to the device's speech-recognition
  service; the AI search sends the query and selected project's expense records
  to the configured provider (which can be Google Gemini, Groq, or OpenRouter).
- Test sign-in, project and expense flows, file selection/download, PDF export,
  and voice search on real Android and iOS devices.
- Keep the signing key and Apple certificate in the store-specific upload
  secret only. Never add them to the repository or build artifacts.
