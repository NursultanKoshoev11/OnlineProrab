CREATE TABLE IF NOT EXISTS project_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    invited_by UUID REFERENCES users(id) ON DELETE SET NULL,
    phone TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('manager', 'worker', 'viewer')),
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_project_invites_project_id
    ON project_invites(project_id);
CREATE INDEX IF NOT EXISTS idx_project_invites_phone
    ON project_invites(phone);
CREATE INDEX IF NOT EXISTS idx_project_invites_active
    ON project_invites(phone, expires_at)
    WHERE accepted_at IS NULL AND revoked_at IS NULL;
