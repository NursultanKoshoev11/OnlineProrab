ALTER TABLE subscription_payment_orders
    ADD COLUMN IF NOT EXISTS bank_app_link TEXT;
