CREATE TABLE IF NOT EXISTS account_subscriptions (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    plan_code TEXT NOT NULL DEFAULT 'trial'
        CHECK (plan_code IN ('trial', 'standard', 'max')),
    status TEXT NOT NULL DEFAULT 'trialing'
        CHECK (status IN ('trialing', 'active', 'expired', 'canceled', 'past_due')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    trial_ends_at TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_subscriptions_status
    ON account_subscriptions(status, current_period_end);

INSERT INTO account_subscriptions (user_id, plan_code, status, started_at, trial_ends_at)
SELECT id, 'trial', 'trialing', created_at, created_at + interval '30 days'
FROM users
ON CONFLICT (user_id) DO NOTHING;
