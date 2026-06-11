package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const uploadMultipartOverhead int64 = 1 * 1024 * 1024

func UploadFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	if strings.TrimSpace(appState.UploadDir) == "" {
		Error(w, http.StatusServiceUnavailable, "file storage is not configured")
		return
	}

	maxBytes := appState.MaxUploadBytes
	if maxBytes <= 0 {
		maxBytes = 10 * 1024 * 1024
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes+uploadMultipartOverhead)
	if err := r.ParseMultipartForm(maxBytes + uploadMultipartOverhead); err != nil {
		Error(w, http.StatusBadRequest, "invalid multipart upload or file too large")
		return
	}

	projectID := strings.TrimSpace(r.FormValue("project_id"))
	kind := strings.ToLower(strings.TrimSpace(r.FormValue("kind")))
	if kind == "" {
		kind = "document"
	}
	if projectID == "" || !isValidFileKind(kind) {
		Error(w, http.StatusBadRequest, "valid project_id and kind are required")
		return
	}

	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if !canContributeToProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	source, header, err := r.FormFile("file")
	if err != nil {
		Error(w, http.StatusBadRequest, "file field is required")
		return
	}
	defer source.Close()

	originalName := sanitizeOriginalName(header.Filename)
	if originalName == "" {
		Error(w, http.StatusBadRequest, "invalid file name")
		return
	}

	stored, err := storeUploadedFile(source, header, projectID, maxBytes)
	if err != nil {
		Error(w, http.StatusBadRequest, err.Error())
		return
	}
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(stored.absolutePath)
		}
	}()

	var item FileDTO
	err = appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO files (project_id, uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id::text, COALESCE(project_id::text, ''), kind, original_name,
		          storage_path, content_type, size_bytes, created_at::text
	`, projectID, userID, kind, originalName, stored.relativePath, stored.contentType, stored.sizeBytes).Scan(
		&item.ID,
		&item.ProjectID,
		&item.Kind,
		&item.OriginalName,
		&item.StoragePath,
		&item.ContentType,
		&item.SizeBytes,
		&item.CreatedAt,
	)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save uploaded file")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'upload', 'file', $3, jsonb_build_object('content_type', $4, 'size_bytes', $5))
	`, userID, projectID, item.ID, item.ContentType, item.SizeBytes)

	cleanup = false
	JSON(w, http.StatusCreated, item)
}

type storedUpload struct {
	absolutePath string
	relativePath string
	contentType  string
	sizeBytes    int64
}

func storeUploadedFile(source multipart.File, header *multipart.FileHeader, projectID string, maxBytes int64) (storedUpload, error) {
	buffer := make([]byte, 512)
	readCount, readErr := io.ReadFull(source, buffer)
	if readErr != nil && readErr != io.ErrUnexpectedEOF && readErr != io.EOF {
		return storedUpload{}, fmt.Errorf("failed to inspect file")
	}
	buffer = buffer[:readCount]
	contentType := http.DetectContentType(buffer)
	if !isAllowedFileType(contentType) {
		return storedUpload{}, fmt.Errorf("unsupported file type")
	}

	extension := extensionForContentType(contentType)
	if extension == "" {
		return storedUpload{}, fmt.Errorf("unsupported file type")
	}
	randomName, err := randomUploadName()
	if err != nil {
		return storedUpload{}, fmt.Errorf("failed to generate storage key")
	}

	datePath := time.Now().UTC().Format("2006/01/02")
	relativePath := filepath.ToSlash(filepath.Join(projectID, datePath, randomName+extension))
	absolutePath := filepath.Join(appState.UploadDir, filepath.FromSlash(relativePath))
	if err := os.MkdirAll(filepath.Dir(absolutePath), 0o750); err != nil {
		return storedUpload{}, fmt.Errorf("failed to prepare file storage")
	}

	destination, err := os.OpenFile(absolutePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		return storedUpload{}, fmt.Errorf("failed to create stored file")
	}
	defer destination.Close()

	written, err := destination.Write(buffer)
	if err != nil {
		_ = os.Remove(absolutePath)
		return storedUpload{}, fmt.Errorf("failed to store file")
	}

	remainingLimit := maxBytes - int64(written)
	if remainingLimit < 0 {
		_ = os.Remove(absolutePath)
		return storedUpload{}, fmt.Errorf("file is too large")
	}
	copied, err := io.Copy(destination, io.LimitReader(source, remainingLimit+1))
	if err != nil {
		_ = os.Remove(absolutePath)
		return storedUpload{}, fmt.Errorf("failed to store file")
	}
	totalSize := int64(written) + copied
	if totalSize > maxBytes {
		_ = os.Remove(absolutePath)
		return storedUpload{}, fmt.Errorf("file is too large")
	}
	if err := destination.Sync(); err != nil {
		_ = os.Remove(absolutePath)
		return storedUpload{}, fmt.Errorf("failed to finalize file")
	}

	_ = header
	return storedUpload{
		absolutePath: absolutePath,
		relativePath: relativePath,
		contentType:  contentType,
		sizeBytes:    totalSize,
	}, nil
}

func sanitizeOriginalName(value string) string {
	name := strings.TrimSpace(filepath.Base(strings.ReplaceAll(value, "\\", "/")))
	if name == "." || name == ".." || len(name) > 255 {
		return ""
	}
	return name
}

func randomUploadName() (string, error) {
	buffer := make([]byte, 16)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

func extensionForContentType(contentType string) string {
	switch contentType {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "application/pdf":
		return ".pdf"
	default:
		return ""
	}
}
