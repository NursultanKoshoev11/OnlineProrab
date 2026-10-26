# Mobile Subscriptions

The app should read subscription state from backend.

Plans:

- Trial: 30 days, 1 active project, owner only, no invited participants.
- Standard: 3,000 KGS/month or 32,400 KGS/year (10% discount), up to 5
  active projects and 5 invited participants per project.
- Max: 5,000 KGS/month or 51,000 KGS/year (15% discount), up to 20 active
  projects and 20 invited participants per project.

Screens:

- Paywall
- Plan selection
- Manage subscription
- Error state
- Billing period selector with monthly and annual pricing
- Payment unavailable state for store builds unless a supported store purchase is configured

States:

- trialing
- active
- expired
- canceled
- past_due

Rules:

- Backend decides access.
- Device state is not enough.
- Restore purchases must sync with backend.
- The project owner pays; invited project members do not pay separately.
- The owner is not counted in the invited participant limit.
- Project limits count active, non-deleted projects.
- Pending invitations count toward the participant limit.
- App Store and Google Play release builds do not launch external O!Bank payment
  links for the digital subscription. An internal sideloaded staging build can
  open the invoice-specific bank link and check payment status after returning.
- The STROY billing website also offers the O!Bank app link on mobile browsers,
  with the bank's hosted web payment as a fallback.
- App Store and Google Play builds must use their store billing systems unless
  the applicable alternative-billing program and storefront are confirmed.
