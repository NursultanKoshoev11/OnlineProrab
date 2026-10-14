package storage

import (
	"bytes"
	"context"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestLocalStoreRoundTripAndTraversalRejection(t *testing.T) {
	store, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local store: %v", err)
	}
	if err := store.Check(context.Background()); err != nil {
		t.Fatalf("local storage health check failed: %v", err)
	}
	content := []byte("private file contents")
	if err := store.Put(context.Background(), "project/2026/receipt.pdf", bytes.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put local object: %v", err)
	}

	object, err := store.Get(context.Background(), "project/2026/receipt.pdf")
	if err != nil {
		t.Fatalf("get local object: %v", err)
	}
	defer object.Body.Close()
	if object.Size != int64(len(content)) {
		t.Fatalf("expected object size %d, got %d", len(content), object.Size)
	}
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read local object: %v", err)
	}
	if !bytes.Equal(actual, content) {
		t.Fatalf("unexpected local object content %q", actual)
	}
	if err := object.Body.Close(); err != nil {
		t.Fatalf("close local object: %v", err)
	}

	for _, key := range []string{"../secret", "project/../secret", "/absolute/key", `project\secret`, "project//secret"} {
		if err := store.Delete(context.Background(), key); err == nil {
			t.Errorf("expected invalid key %q to be rejected", key)
		}
	}
	if err := store.Delete(context.Background(), "project/2026/receipt.pdf"); err != nil {
		t.Fatalf("delete local object: %v", err)
	}
	if err := store.Delete(context.Background(), "project/2026/receipt.pdf"); err != nil {
		t.Fatalf("repeated local deletion should be idempotent: %v", err)
	}
}

func TestLocalStoreRequiresExactObjectSize(t *testing.T) {
	store, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local store: %v", err)
	}
	if err := store.Put(context.Background(), "project/file.pdf", strings.NewReader("short"), 10, "application/pdf"); err == nil {
		t.Fatal("expected short object body to be rejected")
	}
	if _, err := os.Stat(filepath.Join(store.root, "project", "file.pdf")); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("failed upload must not leave a partial object, got %v", err)
	}
}

func TestS3StoreUsesPrivateBucketAndSupportsObjectOperations(t *testing.T) {
	var storedBody []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead {
			if !strings.HasPrefix(r.URL.Path, "/stroy-test") {
				t.Errorf("unexpected S3 health-check path %q", r.URL.Path)
			}
		} else if r.URL.Path != "/stroy-test/project/2026/receipt.pdf" {
			t.Errorf("unexpected S3 request path %q", r.URL.Path)
		}
		if r.Header.Get("Authorization") == "" {
			t.Error("S3 request is not signed")
		}
		switch r.Method {
		case http.MethodPut:
			if got := r.Header.Get("Content-Type"); got != "application/pdf" {
				t.Errorf("unexpected upload content type %q", got)
			}
			var err error
			storedBody, err = io.ReadAll(r.Body)
			if err != nil {
				t.Errorf("read upload body: %v", err)
			}
			w.Header().Set("ETag", `"etag"`)
			w.WriteHeader(http.StatusOK)
		case http.MethodGet:
			w.Header().Set("Content-Length", strconv.Itoa(len(storedBody)))
			w.Header().Set("Content-Type", "application/pdf")
			_, _ = w.Write(storedBody)
		case http.MethodDelete:
			w.WriteHeader(http.StatusNoContent)
		case http.MethodHead:
			w.WriteHeader(http.StatusOK)
		default:
			t.Errorf("unexpected S3 method %q", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	store, err := NewS3(context.Background(), S3Options{
		Region:          "us-east-1",
		Bucket:          "stroy-test",
		Endpoint:        server.URL,
		AccessKeyID:     "test-access-key",
		SecretAccessKey: "test-secret-key",
		ForcePathStyle:  true,
	})
	if err != nil {
		t.Fatalf("create S3 store: %v", err)
	}
	if err := store.Check(context.Background()); err != nil {
		t.Fatalf("S3 health check failed: %v", err)
	}

	content := []byte("private S3 object")
	key := "project/2026/receipt.pdf"
	if err := store.Put(context.Background(), key, bytes.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put S3 object: %v", err)
	}
	if !bytes.Equal(storedBody, content) {
		t.Fatalf("unexpected S3 upload body %q", storedBody)
	}

	object, err := store.Get(context.Background(), key)
	if err != nil {
		t.Fatalf("get S3 object: %v", err)
	}
	defer object.Body.Close()
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read S3 object body: %v", err)
	}
	if !bytes.Equal(actual, content) || object.Size != int64(len(content)) {
		t.Fatalf("unexpected S3 object: size=%d body=%q", object.Size, actual)
	}
	if err := store.Delete(context.Background(), key); err != nil {
		t.Fatalf("delete S3 object: %v", err)
	}
}

func TestS3StoreMapsNotFoundToFilesystemNotExist(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()
	store, err := NewS3(context.Background(), S3Options{
		Region:          "us-east-1",
		Bucket:          "stroy-test",
		Endpoint:        server.URL,
		AccessKeyID:     "test-access-key",
		SecretAccessKey: "test-secret-key",
		ForcePathStyle:  true,
	})
	if err != nil {
		t.Fatalf("create S3 store: %v", err)
	}
	if _, err := store.Get(context.Background(), "project/missing.pdf"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("expected missing object to map to fs.ErrNotExist, got %v", err)
	}
}
