ALTER TABLE projects ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE cost_items ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE daily_reports ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE files ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_role_check') THEN
        ALTER TABLE users ADD CONSTRAINT users_role_check
            CHECK (role IN ('owner', 'manager', 'worker', 'viewer')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'projects_status_check') THEN
        ALTER TABLE projects ADD CONSTRAINT projects_status_check
            CHECK (status IN ('active', 'archived')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'project_members_role_check') THEN
        ALTER TABLE project_members ADD CONSTRAINT project_members_role_check
            CHECK (role IN ('owner', 'manager', 'worker', 'viewer')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_status_check') THEN
        ALTER TABLE tasks ADD CONSTRAINT tasks_status_check
            CHECK (status IN ('open', 'in_progress', 'done', 'cancelled')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'cost_items_currency_check') THEN
        ALTER TABLE cost_items ADD CONSTRAINT cost_items_currency_check
            CHECK (currency IN ('KGS', 'USD', 'KZT')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'files_kind_check') THEN
        ALTER TABLE files ADD CONSTRAINT files_kind_check
            CHECK (kind IN ('receipt', 'photo', 'document')) NOT VALID;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'audit_logs_project_id_fkey'
    ) THEN
        ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_project_id_fkey;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'audit_logs_project_id_fkey'
    ) THEN
        ALTER TABLE audit_logs
            ADD CONSTRAINT audit_logs_project_id_fkey
            FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_projects_active
    ON projects(owner_id, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_cost_items_project_created
    ON cost_items(project_id, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_daily_reports_project_date_active
    ON daily_reports(project_id, report_date DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_files_project_created
    ON files(project_id, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_project_status_active
    ON tasks(project_id, status)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to
    ON tasks(assigned_to)
    WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_project_created
    ON audit_logs(project_id, created_at DESC);
