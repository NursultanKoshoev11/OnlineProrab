# Mobile Subscriptions

The app should read subscription state from backend.

Screens:

- Paywall
- Plan selection
- Manage subscription
- Error state

States:

- free
- trialing
- active
- expired
- canceled

Rules:

- Backend decides access.
- Device state is not enough.
- Restore purchases must sync with backend.
