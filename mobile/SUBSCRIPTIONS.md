# Mobile Subscriptions

The app should read subscription state from backend.

Screens:

- Paywall
- Plan selection
- Manage subscription
- Error state
- Owner payment screen with MBANK and Optima Bank UI
- QR payment preview for the demo APK

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
- The current mobile implementation is UI-only until official bank access and
  payment verification endpoints are available.
