CREATE TABLE IF NOT EXISTS sms_login_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sms_login_codes_phone_created_at
    ON sms_login_codes(phone, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sms_login_codes_expires_at
    ON sms_login_codes(expires_at);
