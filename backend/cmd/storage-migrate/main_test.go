package main

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

func TestMigrationS3OptionsIncludeRequiredBuckets(t *testing.T) {
	cfg := config.Config{
		S3Region:               "us-east-1",
		S3Bucket:               "onlineprorab-uploads",
		S3DeletionLedgerBucket: "onlineprorab-deletions",
	}
	options := migrationS3Options(cfg)
	if options.Region != cfg.S3Region || options.Bucket != cfg.S3Bucket || options.DeletionLedgerBucket != cfg.S3DeletionLedgerBucket {
		t.Fatalf("unexpected migration S3 options: %+v", options)
	}
}

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

func TestCopyAndVerifyStreamsObjectsLargerThan64MiB(t *testing.T) {
	size := int64(64*1024*1024) + 1
	source := &generatedObjectStore{size: size}
	target := &generatedObjectStore{size: size}
	if err := copyAndVerify(context.Background(), source, target, "project/large.bin", size, "application/octet-stream"); err != nil {
		t.Fatalf("stream large object: %v", err)
	}
	if target.bytesWritten != size {
		t.Fatalf("expected %d streamed bytes, got %d", size, target.bytesWritten)
	}
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

func (*testObjectStore) PutStream(context.Context, string, io.Reader, int64, string) error {
	return nil
}

type generatedObjectStore struct {
	size         int64
	bytesWritten int64
}

func (s *generatedObjectStore) Put(_ context.Context, key string, source io.ReadSeeker, size int64, contentType string) error {
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return err
	}
	return s.PutStream(context.Background(), key, source, size, contentType)
}

func (s *generatedObjectStore) PutStream(_ context.Context, _ string, source io.Reader, size int64, _ string) error {
	written, err := io.CopyN(io.Discard, source, size)
	s.bytesWritten = written
	if err != nil {
		return err
	}
	if written != size {
		return io.ErrUnexpectedEOF
	}
	return nil
}

func (s *generatedObjectStore) Get(context.Context, string) (storage.Object, error) {
	return storage.Object{
		Body: io.NopCloser(&repeatedByteReader{remaining: s.size}),
		Size: s.size,
	}, nil
}

func (*generatedObjectStore) Delete(context.Context, string) error { return nil }

type repeatedByteReader struct {
	remaining int64
}

func (r *repeatedByteReader) Read(buffer []byte) (int, error) {
	if r.remaining == 0 {
		return 0, io.EOF
	}
	if int64(len(buffer)) > r.remaining {
		buffer = buffer[:int(r.remaining)]
	}
	for index := range buffer {
		buffer[index] = 'x'
	}
	r.remaining -= int64(len(buffer))
	return len(buffer), nil
}
