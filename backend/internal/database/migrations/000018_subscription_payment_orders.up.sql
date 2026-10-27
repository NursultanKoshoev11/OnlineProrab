CREATE TABLE IF NOT EXISTS subscription_payment_orders (
    order_id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    plan_code TEXT NOT NULL CHECK (plan_code IN ('standard', 'max')),
    billing_period TEXT NOT NULL CHECK (billing_period IN ('month', 'year')),
    amount_kgs INTEGER NOT NULL CHECK (amount_kgs > 0),
    amount_kopecks BIGINT NOT NULL CHECK (amount_kopecks = amount_kgs * 100),
    currency TEXT NOT NULL DEFAULT 'KGS' CHECK (currency = 'KGS'),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'paid', 'canceled')),
    provider_invoice_id TEXT,
    provider_transaction_id TEXT,
    payment_url TEXT,
    status_checked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at TIMESTAMPTZ,
    UNIQUE (user_id, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_payment_invoice_id
    ON subscription_payment_orders(provider_invoice_id)
    WHERE provider_invoice_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_payment_transaction_id
    ON subscription_payment_orders(provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_payment_user_status
    ON subscription_payment_orders(user_id, status, created_at DESC);
