# Subscriptions

OnlineProrab should use subscriptions for premium digital features.

Recommended MVP plans:

- Free: one project, basic expenses, basic reports.
- Pro: multiple projects, team access, file storage, weekly reports.
- Business: unlimited projects, advanced analytics, exports, priority support.

Mobile purchases:

- iOS: App Store Connect products + StoreKit.
- Android: Google Play Console products + Play Billing.

Bank checkout:

- Android and iOS builds do not launch external bank payment links for the
  digital subscription. All payments start on the STROY billing website. When
  the app returns from the browser, it refreshes subscription state from the
  backend so a verified website payment unlocks the phone app.
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
