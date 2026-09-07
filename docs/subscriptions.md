# Subscriptions

OnlineProrab should use subscriptions for premium digital features.

Recommended MVP plans:

- Free: one project, basic expenses, basic reports.
- Pro: multiple projects, team access, file storage, weekly reports.
- Business: unlimited projects, advanced analytics, exports, priority support.

Mobile purchases:

- iOS: App Store Connect products + StoreKit.
- Android: Google Play Console products + Play Billing.

Local bank UI:

- The mobile UI includes MBANK and Optima Bank choices plus a demo QR preview.
- No public Flutter SDK or payment-verification API was found in the banks'
  public developer materials during this implementation.
- Do not unlock a plan from a screenshot or client-side flag. The backend must
  verify a business payment callback or a bank-approved payment reference.
- The project owner owns the subscription; invited members consume the owner's
  participant limit and do not purchase separate plans.

Backend must store subscription state after purchase verification.

Required backend states:

- inactive
- trialing
- active
- grace_period
- expired
- canceled

Do not trust only the mobile app. The server must verify purchase tokens or server notifications before enabling premium features.
