package database

import (
	"context"
	"fmt"
)

const refreshSessionMigrationVersion = 3

func (db *DB) EnsureSessionSchema(ctx context.Context) error {
	if db == nil || db.Pool == nil {
		return fmt.Errorf("database pool is not initialized")
	}

	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin refresh session migration: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(748392015)`); err != nil {
		return fmt.Errorf("lock refresh session migration: %w", err)
	}

	var applied bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, refreshSessionMigrationVersion).Scan(&applied); err != nil {
		return fmt.Errorf("check refresh session migration: %w", err)
	}
	if applied {
		return tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS refresh_sessions (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			token_hash TEXT NOT NULL UNIQUE,
			device_name TEXT,
			expires_at TIMESTAMPTZ NOT NULL,
			revoked_at TIMESTAMPTZ,
			last_used_at TIMESTAMPTZ,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);
		CREATE INDEX IF NOT EXISTS idx_refresh_sessions_user_id ON refresh_sessions(user_id);
		CREATE INDEX IF NOT EXISTS idx_refresh_sessions_expires_at ON refresh_sessions(expires_at);
		CREATE INDEX IF NOT EXISTS idx_refresh_sessions_active ON refresh_sessions(user_id, expires_at) WHERE revoked_at IS NULL;
	`); err != nil {
		return fmt.Errorf("apply refresh session migration: %w", err)
	}

	if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES ($1, 'refresh_sessions')`, refreshSessionMigrationVersion); err != nil {
		return fmt.Errorf("record refresh session migration: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit refresh session migration: %w", err)
	}
	return nil
}
