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
	key := "project/file.pdf"
	if err := source.Put(context.Background(), key, strings.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put source object: %v", err)
	}
	oldContent := "keep destination intact"
	if err := target.Put(context.Background(), key, strings.NewReader(oldContent), int64(len(oldContent)), "application/pdf"); err != nil {
		t.Fatalf("put existing destination object: %v", err)
	}
	if err := copyAndVerify(context.Background(), source, target, key, int64(len(content)+1), "application/pdf"); err == nil {
		t.Fatal("expected the migration to reject a database size mismatch")
	}
	assertObjectContent(t, target, key, oldContent)
}

func TestCopyAndVerifyRejectsOversizedObjectBeforeReadingOrWriting(t *testing.T) {
	ctx := context.Background()
	target, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create target store: %v", err)
	}
	key := "project/file.pdf"
	oldContent := "keep destination intact"
	if err := target.Put(ctx, key, strings.NewReader(oldContent), int64(len(oldContent)), "application/pdf"); err != nil {
		t.Fatalf("put existing destination object: %v", err)
	}

	source := &testObjectStore{
		body: "must not be read",
		size: maxMigrationObjectBytes + 1,
	}
	err = copyAndVerify(ctx, source, target, key, maxMigrationObjectBytes+1, "application/pdf")
	if err == nil || !strings.Contains(err.Error(), "64 MiB") {
		t.Fatalf("expected the migration size limit error, got %v", err)
	}
	if source.gets != 0 {
		t.Fatal("oversized source should be rejected before it is read")
	}
	assertObjectContent(t, target, key, oldContent)
}

func TestCopyAndVerifyRejectsShortSourceWithoutChangingDestination(t *testing.T) {
	ctx := context.Background()
	target, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create target store: %v", err)
	}
	key := "project/file.pdf"
	oldContent := "keep destination intact"
	if err := target.Put(ctx, key, strings.NewReader(oldContent), int64(len(oldContent)), "application/pdf"); err != nil {
		t.Fatalf("put existing destination object: %v", err)
	}
	expectedSize := int64(len("expected source content"))
	source := &testObjectStore{body: "short", size: expectedSize}
	if err := copyAndVerify(ctx, source, target, key, expectedSize, "application/pdf"); err == nil {
		t.Fatal("expected the migration to reject a short source body")
	}
	assertObjectContent(t, target, key, oldContent)
}

func assertObjectContent(t *testing.T, store storage.ObjectStore, key, expected string) {
	t.Helper()
	object, err := store.Get(context.Background(), key)
	if err != nil {
		t.Fatalf("get object %q: %v", key, err)
	}
	defer object.Body.Close()
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read object %q: %v", key, err)
	}
	if string(actual) != expected {
		t.Fatalf("expected object %q to contain %q, got %q", key, expected, actual)
	}
}

type testObjectStore struct {
	body string
	size int64
	gets int
}

func (*testObjectStore) Put(context.Context, string, io.ReadSeeker, int64, string) error {
	return nil
}

func (s *testObjectStore) Get(context.Context, string) (storage.Object, error) {
	s.gets++
	return storage.Object{Body: io.NopCloser(strings.NewReader(s.body)), Size: s.size}, nil
}

func (*testObjectStore) Delete(context.Context, string) error { return nil }
