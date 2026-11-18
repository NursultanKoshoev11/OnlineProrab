CREATE TABLE IF NOT EXISTS expense_ai_search_attempts (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_expense_ai_search_attempts_user_created
    ON expense_ai_search_attempts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_expense_ai_search_attempts_created
    ON expense_ai_search_attempts(created_at);
