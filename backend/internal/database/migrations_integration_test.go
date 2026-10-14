package database

import (
	"context"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
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
		"file_storage_deletions",
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
	var descriptionColumnExists bool
	if err := db.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM information_schema.columns
			WHERE table_schema = 'public'
			  AND table_name = 'cost_items'
			  AND column_name = 'description'
		)
	`).Scan(&descriptionColumnExists); err != nil {
		t.Fatalf("check cost item description column: %v", err)
	}
	if !descriptionColumnExists {
		t.Fatal("expected cost_items.description to exist after migrations")
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
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO files (uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
		VALUES ($1, 'document', 'account-file.pdf', 'account/delete-me.pdf', 'application/pdf', 1)
	`, userID); err != nil {
		t.Fatalf("insert account file: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID); err != nil {
		t.Fatalf("delete migration test user: %v", err)
	}
	var queuedDeletions int
	if err := db.Pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM file_storage_deletions WHERE storage_path = 'account/delete-me.pdf'
	`).Scan(&queuedDeletions); err != nil {
		t.Fatalf("check account file deletion queue: %v", err)
	}
	if queuedDeletions != 1 {
		t.Fatalf("expected account file removal to be queued by database trigger, got %d rows", queuedDeletions)
	}
	store := &migrationTestObjectStore{deleted: make(chan string, 1), events: make(chan string, 2)}
	workerCtx, stopWorker := context.WithCancel(context.Background())
	defer stopWorker()
	go storage.RunDeletionWorker(workerCtx, db.Pool, store)
	select {
	case event := <-store.events:
		if event != "journal:account/delete-me.pdf" {
			t.Fatalf("expected the deletion journal before the object delete, got %q", event)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("storage deletion worker did not record its durable tombstone")
	}
	select {
	case event := <-store.events:
		if event != "delete:account/delete-me.pdf" {
			t.Fatalf("expected object deletion after its tombstone, got %q", event)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("storage deletion worker did not delete the queued object")
	}
	select {
	case key := <-store.deleted:
		if key != "account/delete-me.pdf" {
			t.Fatalf("worker deleted unexpected object %q", key)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("storage deletion worker did not report the deleted object")
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		var remainingDeletions int
		if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM file_storage_deletions`).Scan(&remainingDeletions); err != nil {
			t.Fatalf("check remaining storage deletions: %v", err)
		}
		if remainingDeletions == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("expected successfully removed object to leave the outbox empty, got %d rows", remainingDeletions)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

type migrationTestObjectStore struct {
	deleted chan string
	events  chan string
}

func (s *migrationTestObjectStore) Put(context.Context, string, io.ReadSeeker, int64, string) error {
	return nil
}

func (s *migrationTestObjectStore) Get(context.Context, string) (storage.Object, error) {
	return storage.Object{}, nil
}

func (s *migrationTestObjectStore) RecordAccountDeletion(context.Context, string) error {
	return nil
}

func (s *migrationTestObjectStore) RecordObjectDeletion(ctx context.Context, key string) error {
	select {
	case s.events <- "journal:" + key:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *migrationTestObjectStore) Delete(ctx context.Context, key string) error {
	if err := s.RecordObjectDeletion(ctx, key); err != nil {
		return err
	}
	select {
	case s.events <- "delete:" + key:
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case s.deleted <- key:
		return nil
	case <-ctx.Done():
		return ctx.Err()
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
