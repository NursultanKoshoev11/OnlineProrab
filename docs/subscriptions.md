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

- App Store and Google Play release builds do not launch external bank payment
  links for the digital subscription. An internal staging build can open the
  invoice-specific O!Bank app link and check payment status after return. The
  billing website also offers the bank app link on mobile browsers, with its
  hosted-paylink fallback.
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
