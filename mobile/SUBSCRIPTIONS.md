# Mobile Subscriptions

The app should read subscription state from backend.

Screens:

- Paywall
- Plan selection
- Manage subscription
- Error state
- Owner payment screen with MBANK and Optima Bank selection
- Server-owned checkout order flow for Optima
- Offline demo checkout with a controlled test completion action

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
- The project owner pays; invited project members do not pay separately.
- Participant limits are counted separately from the owner.
- The live Optima adapter is intentionally fail-closed until the bank supplies
  its official signed API/webhook contract. The app opens only a URL returned
  by the backend; it never contains bank secrets or accepts a client-side
  success as proof of payment.
