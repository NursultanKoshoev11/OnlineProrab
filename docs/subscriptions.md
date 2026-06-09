# Subscriptions

OnlineProrab should use subscriptions for premium digital features.

Recommended MVP plans:

- Free: one project, basic expenses, basic reports.
- Pro: multiple projects, team access, file storage, weekly reports.
- Business: unlimited projects, advanced analytics, exports, priority support.

Mobile purchases:

- iOS: App Store Connect products + StoreKit.
- Android: Google Play Console products + Play Billing.

Backend must store subscription state after purchase verification.

Required backend states:

- inactive
- trialing
- active
- grace_period
- expired
- canceled

Do not trust only the mobile app. The server must verify purchase tokens or server notifications before enabling premium features.
