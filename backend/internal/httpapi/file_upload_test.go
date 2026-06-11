package httpapi

import (
	"bytes"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestSanitizeOriginalName(t *testing.T) {
	cases := map[string]string{
		"receipt.jpg":              "receipt.jpg",
		"../receipt.jpg":           "receipt.jpg",
		`C:\\temp\\receipt.jpg`: "receipt.jpg",
		"..":                       "",
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

func TestStoreUploadedJPEG(t *testing.T) {
	oldUploadDir := appState.UploadDir
	appState.UploadDir = t.TempDir()
	defer func() { appState.UploadDir = oldUploadDir }()

	jpeg := append([]byte{0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00}, bytes.Repeat([]byte{0x01}, 100)...)
	stored, err := storeUploadedFile(
		&memoryMultipartFile{Reader: bytes.NewReader(jpeg)},
		&multipart.FileHeader{Filename: "receipt.jpg"},
		"project-1",
		1024,
	)
	if err != nil {
		t.Fatalf("storeUploadedFile returned error: %v", err)
	}
	defer os.Remove(stored.absolutePath)

	if stored.contentType != "image/jpeg" {
		t.Fatalf("expected image/jpeg, got %q", stored.contentType)
	}
	if stored.sizeBytes != int64(len(jpeg)) {
		t.Fatalf("expected size %d, got %d", len(jpeg), stored.sizeBytes)
	}
	if filepath.Ext(stored.absolutePath) != ".jpg" {
		t.Fatalf("expected .jpg extension, got %q", stored.absolutePath)
	}
	if _, err := os.Stat(stored.absolutePath); err != nil {
		t.Fatalf("stored file does not exist: %v", err)
	}
}

func TestStoreUploadedFileRejectsUnsupportedType(t *testing.T) {
	oldUploadDir := appState.UploadDir
	appState.UploadDir = t.TempDir()
	defer func() { appState.UploadDir = oldUploadDir }()

	_, err := storeUploadedFile(
		&memoryMultipartFile{Reader: bytes.NewReader([]byte("plain text"))},
		&multipart.FileHeader{Filename: "notes.txt"},
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

type memoryMultipartFile struct {
	*bytes.Reader
}

func (f *memoryMultipartFile) Close() error { return nil }
