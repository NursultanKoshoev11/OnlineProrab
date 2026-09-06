package database

import (
	"context"
	"os"
	"strings"
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
	if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM schema_migrations WHERE version BETWEEN 1 AND 11`).Scan(&applied); err != nil {
		t.Fatalf("count migrations: %v", err)
	}
	if applied != 11 {
		t.Fatalf("expected 11 applied migrations, got %d", applied)
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
		"auth_attempts",
	} {
		var exists bool
		if err := db.Pool.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
			t.Fatalf("check table %s: %v", table, err)
		}
		if !exists {
			t.Fatalf("expected table %s to exist", table)
		}
	}

	var constraintDefinition string
	if err := db.Pool.QueryRow(ctx, `
		SELECT pg_get_constraintdef(oid)
		FROM pg_constraint
		WHERE conname = 'files_kind_check'
	`).Scan(&constraintDefinition); err != nil {
		t.Fatalf("read files kind constraint: %v", err)
	}
	if !strings.Contains(constraintDefinition, "project_cover") {
		t.Fatalf("files_kind_check does not allow project_cover: %s", constraintDefinition)
	}
	var constraintValidated bool
	if err := db.Pool.QueryRow(ctx, `
		SELECT convalidated
		FROM pg_constraint
		WHERE conname = 'files_kind_check'
	`).Scan(&constraintValidated); err != nil {
		t.Fatalf("read files kind constraint validation: %v", err)
	}
	if !constraintValidated {
		t.Fatal("files_kind_check must be validated after migrations")
	}

	if err := db.Pool.QueryRow(ctx, `
		SELECT convalidated
		FROM pg_constraint
		WHERE conname = 'cost_items_receipt_file_fk'
	`).Scan(&constraintValidated); err != nil {
		t.Fatalf("read receipt foreign key validation: %v", err)
	}
	if !constraintValidated {
		t.Fatal("cost_items_receipt_file_fk must be validated after migrations")
	}

	var budgetColumns int
	if err := db.Pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM information_schema.columns
		WHERE table_schema = 'public'
		  AND table_name = 'projects'
		  AND column_name IN ('budget_amount', 'currency')
	`).Scan(&budgetColumns); err != nil {
		t.Fatalf("check project budget columns: %v", err)
	}
	if budgetColumns != 2 {
		t.Fatalf("expected project budget columns, got %d", budgetColumns)
	}

	var userID string
	if err := db.Pool.QueryRow(ctx, `
		INSERT INTO users (phone, name)
		VALUES ('+996555000009', 'Migration test')
		RETURNING id::text
	`).Scan(&userID); err != nil {
		t.Fatalf("insert migration test user: %v", err)
	}
	var projectBudget float64
	var projectCurrency string
	if err := db.Pool.QueryRow(ctx, `
		INSERT INTO projects (owner_id, name)
		VALUES ($1, 'Migration test project')
		RETURNING budget_amount::float8, currency
	`, userID).Scan(&projectBudget, &projectCurrency); err != nil {
		t.Fatalf("insert migration test project: %v", err)
	}
	if projectBudget != 0 || projectCurrency != "KGS" {
		t.Fatalf("unexpected project defaults: budget=%v currency=%s", projectBudget, projectCurrency)
	}

	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO files (kind, original_name, storage_path, content_type, size_bytes)
		VALUES ('project_cover', 'cover.jpg', 'projects/cover.jpg', 'image/jpeg', 1)
	`); err != nil {
		t.Fatalf("insert project cover file: %v", err)
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
