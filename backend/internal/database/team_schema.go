package database

import (
	"context"
	"fmt"
)

const projectInvitesMigrationVersion = 4

func (db *DB) EnsureTeamSchema(ctx context.Context) error {
	if db == nil || db.Pool == nil {
		return fmt.Errorf("database pool is not initialized")
	}

	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin project invites migration: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(748392015)`); err != nil {
		return fmt.Errorf("lock project invites migration: %w", err)
	}

	var applied bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, projectInvitesMigrationVersion).Scan(&applied); err != nil {
		return fmt.Errorf("check project invites migration: %w", err)
	}
	if applied {
		return tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx, `
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
		CREATE INDEX IF NOT EXISTS idx_project_invites_project_id ON project_invites(project_id);
		CREATE INDEX IF NOT EXISTS idx_project_invites_phone ON project_invites(phone);
		CREATE INDEX IF NOT EXISTS idx_project_invites_active ON project_invites(phone, expires_at) WHERE accepted_at IS NULL AND revoked_at IS NULL;
	`); err != nil {
		return fmt.Errorf("apply project invites migration: %w", err)
	}

	if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES ($1, 'project_invites')`, projectInvitesMigrationVersion); err != nil {
		return fmt.Errorf("record project invites migration: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit project invites migration: %w", err)
	}
	return nil
}
