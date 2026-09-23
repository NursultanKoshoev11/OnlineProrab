ALTER TABLE account_subscriptions
    ADD COLUMN IF NOT EXISTS billing_period TEXT NOT NULL DEFAULT 'month';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'account_subscriptions_billing_period_check'
    ) THEN
        ALTER TABLE account_subscriptions
            ADD CONSTRAINT account_subscriptions_billing_period_check
            CHECK (billing_period IN ('month', 'year'));
    END IF;
END $$;
