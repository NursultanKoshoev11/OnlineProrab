package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

func TestFileDTODoesNotExposeStoragePath(t *testing.T) {
	payload, err := json.Marshal(FileDTO{ID: "file-1", StoragePath: "private/secret.jpg"})
	if err != nil {
		t.Fatalf("marshal FileDTO: %v", err)
	}
	if strings.Contains(string(payload), "storage_path") || strings.Contains(string(payload), "secret.jpg") {
		t.Fatalf("FileDTO exposed internal storage path: %s", payload)
	}
}

func TestSanitizeOriginalName(t *testing.T) {
	cases := map[string]string{
		"receipt.jpg":           "receipt.jpg",
		"../receipt.jpg":        "receipt.jpg",
		`C:\\temp\\receipt.jpg`: "receipt.jpg",
		"..":                    "",
	}
	for input, expected := range cases {
		if got := sanitizeOriginalName(input); got != expected {
			t.Fatalf("sanitizeOriginalName(%q)=%q, expected %q", input, got, expected)
		}
	}
}

func TestExtensionForContentType(t *testing.T) {
	cases := map[string]string{
		"image/jpeg":      ".jpg",
		"image/png":       ".png",
		"image/webp":      ".webp",
		"application/pdf": ".pdf",
		"text/plain":      "",
	}
	for contentType, expected := range cases {
		if got := extensionForContentType(contentType); got != expected {
			t.Fatalf("extensionForContentType(%q)=%q, expected %q", contentType, got, expected)
		}
	}
}

func TestProjectCoverAcceptsImagesOnly(t *testing.T) {
	for _, contentType := range []string{"image/jpeg", "image/png", "image/webp"} {
		if !isAllowedProjectCoverType(contentType) {
			t.Errorf("expected project cover type %q to be accepted", contentType)
		}
	}
	if isAllowedProjectCoverType("application/pdf") {
		t.Fatal("project cover must reject PDF files")
	}
}

func TestStoreUploadedJPEG(t *testing.T) {
	store, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local storage: %v", err)
	}

	jpeg := append([]byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00}, bytes.Repeat([]byte{0x01}, 100)...)
	stored, err := storeUploadedFile(
		context.Background(),
		store,
		&memoryMultipartFile{Reader: bytes.NewReader(jpeg)},
		"project-1",
		1024,
	)
	if err != nil {
		t.Fatalf("storeUploadedFile returned error: %v", err)
	}
	if stored.contentType != "image/jpeg" {
		t.Fatalf("expected image/jpeg, got %q", stored.contentType)
	}
	if stored.sizeBytes != int64(len(jpeg)) {
		t.Fatalf("expected size %d, got %d", len(jpeg), stored.sizeBytes)
	}
	if filepath.Ext(stored.relativePath) != ".jpg" {
		t.Fatalf("expected .jpg extension, got %q", stored.relativePath)
	}
	object, err := store.Get(context.Background(), stored.relativePath)
	if err != nil {
		t.Fatalf("stored file does not exist: %v", err)
	}
	defer object.Body.Close()
	actual, err := io.ReadAll(object.Body)
	if err != nil || !bytes.Equal(actual, jpeg) {
		t.Fatalf("stored file content mismatch: err=%v", err)
	}
}

func TestStoreUploadedFileRejectsUnsupportedType(t *testing.T) {
	store, err := storage.NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local storage: %v", err)
	}

	_, err = storeUploadedFile(
		context.Background(),
		store,
		&memoryMultipartFile{Reader: bytes.NewReader([]byte("plain text"))},
		"project-1",
		1024,
	)
	if err == nil {
		t.Fatal("expected unsupported file type error")
	}
}

func TestMultipartUploadBypassesJSONBodyLimit(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/v1/files/upload", nil)
	req.Header.Set("Content-Type", "multipart/form-data; boundary=test")
	if shouldLimitJSONBody(req) {
		t.Fatal("expected multipart upload to bypass JSON body limit")
	}
}

func TestResolveStoredFilePathRejectsTraversalAndAcceptsNestedPath(t *testing.T) {
	root := t.TempDir()
	if resolved, ok := resolveStoredFilePath(root, `project\2026\receipt.jpg`); !ok {
		t.Fatal("expected normalized nested path to be accepted")
	} else if !strings.HasPrefix(resolved, filepath.Clean(root)+string(filepath.Separator)) {
		t.Fatalf("resolved path escaped upload root: %q", resolved)
	}

	for _, value := range []string{"../secret.jpg", `project\..\secret.jpg`, "/tmp/secret.jpg", "C:\\secret.jpg"} {
		if _, ok := resolveStoredFilePath(root, value); ok {
			t.Fatalf("expected unsafe storage path %q to be rejected", value)
		}
	}
}

type memoryMultipartFile struct {
	*bytes.Reader
}

func (f *memoryMultipartFile) Close() error { return nil }
