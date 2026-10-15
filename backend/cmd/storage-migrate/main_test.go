package main

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

func TestCopyAndVerifyCopiesAndChecksObject(t *testing.T) {
	source, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create source store: %v", err)
	}
	target, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create target store: %v", err)
	}

	content := "migration test object"
	key := "project/2026/receipt.pdf"
	if err := source.Put(context.Background(), key, strings.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put source object: %v", err)
	}
	if err := copyAndVerify(context.Background(), source, target, key, int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("copy and verify object: %v", err)
	}

	object, err := target.Get(context.Background(), key)
	if err != nil {
		t.Fatalf("get target object: %v", err)
	}
	defer object.Body.Close()
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read target object: %v", err)
	}
	if string(actual) != content {
		t.Fatalf("expected target content %q, got %q", content, actual)
	}
}

func TestCopyAndVerifyRejectsMismatchWithDatabaseSize(t *testing.T) {
	source, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create source store: %v", err)
	}
	target, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create target store: %v", err)
	}
	content := "actual"
	if err := source.Put(context.Background(), "project/file.pdf", strings.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put source object: %v", err)
	}
	if err := copyAndVerify(context.Background(), source, target, "project/file.pdf", int64(len(content)+1), "application/pdf"); err == nil {
		t.Fatal("expected the migration to reject a database size mismatch")
	}
}
