package database

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestApplyMigrationsOnCleanDatabase(t *testing.T) {
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not configured")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	db, err := Open(ctx, url)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	defer db.Close()

	if err := resetMigrationTestDatabase(ctx, db); err != nil {
		t.Fatalf("reset test database: %v", err)
	}
	if err := db.ApplyMigrations(ctx); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	if err := db.ApplyMigrations(ctx); err != nil {
		t.Fatalf("reapply migrations: %v", err)
	}

	var applied int
	if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM schema_migrations WHERE version BETWEEN 1 AND 4`).Scan(&applied); err != nil {
		t.Fatalf("count migrations: %v", err)
	}
	if applied != 4 {
		t.Fatalf("expected 4 applied migrations, got %d", applied)
	}

	for _, table := range []string{
		"users",
		"projects",
		"project_members",
		"cost_items",
		"daily_reports",
		"tasks",
		"files",
		"audit_logs",
		"sms_login_codes",
		"refresh_sessions",
		"project_invites",
	} {
		var exists bool
		if err := db.Pool.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
			t.Fatalf("check table %s: %v", table, err)
		}
		if !exists {
			t.Fatalf("expected table %s to exist", table)
		}
	}
}

func resetMigrationTestDatabase(ctx context.Context, db *DB) error {
	_, err := db.Pool.Exec(ctx, `
		DROP SCHEMA public CASCADE;
		CREATE SCHEMA public;
		GRANT ALL ON SCHEMA public TO public;
	`)
	return err
}
