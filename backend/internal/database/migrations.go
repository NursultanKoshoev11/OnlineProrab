package database

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
)

//go:embed migrations/*.up.sql
var migrationFiles embed.FS

const migrationAdvisoryLock int64 = 748392015

const legacyProductionConstraintsMigrationName = "production_constraints"

func (db *DB) ApplyMigrations(ctx context.Context) error {
	if db == nil || db.Pool == nil {
		return fmt.Errorf("database pool is not initialized")
	}
	if err := db.reconcileLegacyProductionConstraints(ctx); err != nil {
		return err
	}

	entries, err := fs.ReadDir(migrationFiles, "migrations")
	if err != nil {
		return fmt.Errorf("read embedded migrations: %w", err)
	}

	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".up.sql") {
			continue
		}
		names = append(names, entry.Name())
	}
	sort.Strings(names)

	for _, name := range names {
		version, err := migrationVersion(name)
		if err != nil {
			return err
		}
		sqlBytes, err := migrationFiles.ReadFile("migrations/" + name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		if err := db.applyMigration(ctx, version, name, string(sqlBytes)); err != nil {
			return err
		}
	}
	return nil
}

// reconcileLegacyProductionConstraints repairs databases created by the old
// EnsureSchema migrator. That migrator also recorded versions 1 and 2, but its
// version 2 did not include the deleted_at columns and other hardening now
// required by migration 11. Apply the current version-2 SQL once before later
// migrations depend on those schema changes.
func (db *DB) reconcileLegacyProductionConstraints(ctx context.Context) error {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin legacy migration reconciliation: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, migrationAdvisoryLock); err != nil {
		return fmt.Errorf("lock legacy migration reconciliation: %w", err)
	}

	var hasMigrationTable bool
	if err := tx.QueryRow(ctx, `SELECT to_regclass('public.schema_migrations') IS NOT NULL`).Scan(&hasMigrationTable); err != nil {
		return fmt.Errorf("check migration history for legacy schema: %w", err)
	}
	if !hasMigrationTable {
		return tx.Commit(ctx)
	}

	var legacyName string
	if err := tx.QueryRow(ctx, `
		SELECT COALESCE((SELECT name FROM schema_migrations WHERE version = 2), '')
	`).Scan(&legacyName); err != nil {
		return fmt.Errorf("read legacy production migration history: %w", err)
	}
	if legacyName != legacyProductionConstraintsMigrationName {
		return tx.Commit(ctx)
	}

	statement, err := migrationFiles.ReadFile("migrations/000002_harden_existing_schema.up.sql")
	if err != nil {
		return fmt.Errorf("read legacy schema reconciliation migration: %w", err)
	}
	if _, err := tx.Exec(ctx, string(statement)); err != nil {
		return fmt.Errorf("reconcile legacy production schema: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE schema_migrations
		SET name = '000002_harden_existing_schema.up.sql'
		WHERE version = 2 AND name = $1
	`, legacyProductionConstraintsMigrationName); err != nil {
		return fmt.Errorf("record legacy schema reconciliation: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit legacy schema reconciliation: %w", err)
	}
	return nil
}

func (db *DB) applyMigration(ctx context.Context, version int64, name, sqlText string) error {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin migration %s: %w", name, err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, migrationAdvisoryLock); err != nil {
		return fmt.Errorf("lock migration %s: %w", name, err)
	}
	if _, err := tx.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version BIGINT PRIMARY KEY,
			name TEXT NOT NULL,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)
	`); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}

	var applied bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, version).Scan(&applied); err != nil {
		return fmt.Errorf("check migration %s: %w", name, err)
	}
	if applied {
		return tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx, sqlText); err != nil {
		return fmt.Errorf("apply migration %s: %w", name, err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES ($1, $2)`, version, name); err != nil {
		return fmt.Errorf("record migration %s: %w", name, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit migration %s: %w", name, err)
	}
	return nil
}

func migrationVersion(name string) (int64, error) {
	prefix, _, ok := strings.Cut(name, "_")
	if !ok {
		return 0, fmt.Errorf("invalid migration filename %q", name)
	}
	version, err := strconv.ParseInt(prefix, 10, 64)
	if err != nil || version <= 0 {
		return 0, fmt.Errorf("invalid migration version in %q", name)
	}
	return version, nil
}
