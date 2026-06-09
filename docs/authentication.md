# Authentication

OnlineProrab should support passwordless login.

## SMS login

Flow:
1. User enters phone number.
2. Backend creates a short-lived one-time code.
3. SMS provider sends the code.
4. User enters the code.
5. Backend verifies the code and returns an app session.

Rules:
- Code must expire quickly.
- Store only a code hash, not the plain code.
- Limit repeated requests.
- Limit repeated verification attempts.
- Do not reveal whether a phone number already exists.

## Telegram login

Telegram login should be handled server-side.

Supported options:
- Telegram Login / OIDC for normal mobile and web login.
- Telegram Mini App init data if we later launch inside Telegram.

Backend must verify Telegram data before creating a session.

## MVP decision

Use SMS as primary login.
Use Telegram as optional fast login.
