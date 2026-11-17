CREATE TABLE IF NOT EXISTS auth_session_bootstrap_tokens (
    token_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_session_bootstrap_tokens_expires_at
    ON auth_session_bootstrap_tokens(expires_at);
