# STROY push notifications

The mobile clients use Firebase Cloud Messaging (FCM). The existing SSE stream
continues to refresh an open workspace; FCM covers background and terminated-app
delivery.

## Firebase project

- Project: `stroy-notifications`
- Android application: `kg.com.stroy.app`
- iOS application: `com.koshoev.stroy`
- Firebase Cloud Messaging API (HTTP v1): enabled

The public mobile Firebase options are checked into
`mobile/lib/firebase_options.dart`. They do not grant server-side access.

## Deployment settings

The API needs these values in the production deployment environment:

- `FCM_PROJECT_ID=stroy-notifications`
- `FCM_SERVICE_ACCOUNT_JSON` — the complete Firebase Admin SDK service-account
  JSON, stored only in the deployment secret manager/GitHub Environment
  `production-api`. The main-branch deployment transfers it over the existing
  verified SSH channel into `/opt/stroy-api/.fcm_service_account.json` with
  mode `0600`, and injects it only into the API container at startup.

Do not commit the JSON or paste it into chat. The API starts without push
delivery when the two values are absent, and logs that push delivery is
disabled. Once configured, the `000025_push_tokens` migration creates the token
registry and `POST /api/v1/push-tokens` registers device tokens.

When a cost item is created, all other members of the project with a registered
token receive an FCM notification. The author still receives the in-app SSE
update but is not sent a duplicate push notification. The notification title is
`Новый расход`; its body includes the actor name (or phone as a fallback),
expense title, amount, and currency, for example:
`Нурсултан добавил расход «Бетон» на 1 250,5 сом`.

## Apple APNs setup

FCM can deliver Android notifications immediately. iOS delivery also requires
an Apple APNs authentication key in Firebase Console → Project settings →
Cloud Messaging → Apple app configuration. Upload the `.p8` key for both
development and production (or use the production key for App Store builds),
then provide the Apple Key ID and Team ID `7RHTX4XXX2`.


