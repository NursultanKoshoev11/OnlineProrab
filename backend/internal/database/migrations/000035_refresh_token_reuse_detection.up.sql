-- Keep the hash of the refresh token that was rotated out last so that a
-- replay of an already-used token can be detected and the session revoked.
ALTER TABLE refresh_sessions ADD COLUMN IF NOT EXISTS previous_token_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_refresh_sessions_previous_token_hash
    ON refresh_sessions(previous_token_hash)
    WHERE previous_token_hash IS NOT NULL;
