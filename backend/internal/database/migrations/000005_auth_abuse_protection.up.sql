CREATE TABLE IF NOT EXISTS auth_attempts (
    id BIGSERIAL PRIMARY KEY,
    phone TEXT,
    remote_key TEXT NOT NULL,
    action TEXT NOT NULL,
    succeeded BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT auth_attempts_action_check CHECK (action IN ('sms_request', 'sms_verify'))
);

CREATE INDEX IF NOT EXISTS idx_auth_attempts_remote_action_created
    ON auth_attempts(remote_key, action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_attempts_phone_action_created
    ON auth_attempts(phone, action, created_at DESC)
    WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_auth_attempts_created_at
    ON auth_attempts(created_at);
