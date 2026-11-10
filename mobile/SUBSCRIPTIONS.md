# Mobile Subscriptions

The app should read subscription state from backend.

Plans:

- Trial: 30 days, 1 active project, owner only, no invited participants.
- Standard: 3,000 KGS/month or 32,400 KGS/year (10% discount), up to 5
  active projects and 5 invited participants per project.
- Max: 5,000 KGS/month or 51,000 KGS/year (15% discount), up to 20 active
  projects and 20 invited participants per project.

In-app subscription information:

- Current plan, access limits, and expiration date
- Active and expired access status
- No in-app plan selection, prices, checkout buttons, or payment directions

States:

- trialing
- active
- expired
- canceled
- past_due

Rules:

- Backend decides access.
- Device state is not enough.
- Backend is the source of truth for subscription access.
- The project owner pays; invited project members do not pay separately.
- The owner is not counted in the invited participant limit.
- Project limits count active, non-deleted projects.
- Pending invitations count toward the participant limit.
- Subscription billing is handled outside the mobile apps. The apps show
  entitlement status only and do not direct users to an external payment flow.
- The app refreshes subscription state from the backend when it resumes, so a
  newly active entitlement is reflected without an in-app purchase prompt.
- Do not add external-payment messaging or links to store builds unless the
  relevant platform program and storefront are confirmed for STROY.
