CREATE TABLE IF NOT EXISTS telegram_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    telegram_id TEXT NOT NULL UNIQUE,
    username TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
