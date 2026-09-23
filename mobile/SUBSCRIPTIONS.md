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
- Payment unavailable state until an official bank checkout and webhook are connected

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
- The current mobile payment flow is UI-only until official bank access and
  payment verification endpoints are available.
