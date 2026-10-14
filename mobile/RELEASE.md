# STROY mobile release

## Android

The signed production AAB is built from the `main` branch by the `Mobile CI`
workflow when `production_release` is set to `true`. Create a GitHub Environment
named `production-mobile`, restrict it to `main`, and configure the values below
as environment variables and secrets. Add required reviewers if signing builds
must wait for an explicit release approval.

- Environment variable `STROY_APPLICATION_ID`: the exact Android package ID registered in
  Google Play.
- Environment secrets `STROY_KEYSTORE_BASE64`, `STROY_KEYSTORE_PASSWORD`,
  `STROY_KEY_ALIAS`, and `STROY_KEY_PASSWORD`: the Play upload keystore and
  credentials.

The workflow validates the release inputs, runs analysis and tests, and saves
the AAB as a GitHub Actions artifact. It does not submit the artifact to Google
Play.

## iOS

The `iOS simulator build` job runs on pull requests and pushes. It compiles the
real iOS target without Apple signing. The signed App Store IPA is built from
the `main` branch by `Mobile CI` when `production_ios_release` is set to `true`.
Use the same `production-mobile` environment and configure the values below
there:

- Environment variable `STROY_IOS_BUNDLE_ID`: the exact App Store Connect bundle ID.
- Environment variable `STROY_IOS_TEAM_ID`: the Apple Developer Team ID that owns that app.
- Environment secret `STROY_IOS_CERTIFICATE_BASE64`: base64-encoded Apple Distribution
  `.p12` certificate.
- Environment secret `STROY_IOS_CERTIFICATE_PASSWORD`: password for that `.p12` file.
- Environment secret `STROY_IOS_PROVISIONING_PROFILE_BASE64`: base64-encoded App Store
  provisioning profile for the same bundle ID and team.

The workflow verifies that the profile team and application identifier match
the configured values, creates a signed IPA, and saves it as a GitHub Actions
artifact. It does not upload the IPA to App Store Connect. The iOS deployment
target is 14.0 because the file picker plugin requires iOS 14 or newer.

## Release checks

- Increment `version` in `pubspec.yaml` according to the next store build
  number; Google Play and App Store Connect require monotonically increasing
  build numbers.
- Confirm the configured Android package ID and iOS bundle ID match their
  store records.
- Complete the app privacy details and provide the public privacy-policy and
  support URLs in each store listing.
- Test sign-in, project and expense flows, file selection/download, PDF export,
  and voice search on real Android and iOS devices.
- Keep the signing key and Apple certificate in the store-specific upload
  secret only. Never add them to the repository or build artifacts.
