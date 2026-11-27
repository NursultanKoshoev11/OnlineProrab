package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

const uploadMultipartOverhead int64 = 1 * 1024 * 1024

// projectStorageQuotaBytes caps the files one project may keep, so a single
// account cannot run up unbounded object-storage cost.
const projectStorageQuotaBytes int64 = 5 * 1024 * 1024 * 1024

func UploadFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	if appState.FileStore == nil {
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
	if kind == "project_cover" && !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}
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

	var usedBytes int64
	if err := appState.DB.Pool.QueryRow(ctx, `SELECT COALESCE(SUM(size_bytes), 0) FROM files WHERE project_id = $1`, projectID).Scan(&usedBytes); err != nil {
		Error(w, http.StatusServiceUnavailable, "file storage is temporarily unavailable")
		return
	}
	if usedBytes+header.Size > projectStorageQuotaBytes {
		Error(w, http.StatusRequestEntityTooLarge, "Хранилище проекта заполнено (5 ГБ). Удалите ненужные файлы.")
		return
	}

	originalName := sanitizeOriginalName(header.Filename)
	if originalName == "" {
		Error(w, http.StatusBadRequest, "invalid file name")
		return
	}

	stored, err := storeUploadedFile(ctx, appState.FileStore, source, projectID, maxBytes)
	if err != nil {
		writeUploadError(w, err)
		return
	}
	cleanup := true
	defer func() {
		if cleanup {
			if err := removeStoredFile(stored.relativePath); err != nil {
				slog.Error("uncommitted_upload_cleanup_failed", "request_id", requestIDFromContext(r.Context()), "error", err)
			}
		}
	}()
	if kind == "project_cover" && !isAllowedProjectCoverType(stored.contentType) {
		Error(w, http.StatusBadRequest, "project cover must be a JPEG, PNG or WebP image")
		return
	}

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
		VALUES ($1, $2, 'upload', 'file', $3, jsonb_build_object('content_type', $4::text, 'size_bytes', $5::bigint))
	`, userID, projectID, item.ID, item.ContentType, item.SizeBytes)
	if kind == "project_cover" {
		archivePreviousProjectCovers(ctx, projectID, item.ID)
	}

	cleanup = false
	publishProjectEvent(projectID, "file", item.ID, "created")
	JSON(w, http.StatusCreated, item)
}

type storedUpload struct {
	relativePath string
	contentType  string
	sizeBytes    int64
}

func storeUploadedFile(ctx context.Context, store storage.ObjectStore, source multipart.File, projectID string, maxBytes int64) (storedUpload, error) {
	if store == nil {
		return storedUpload{}, fmt.Errorf("file storage is not configured")
	}
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
	destination, err := os.CreateTemp("", ".stroy-upload-*")
	if err != nil {
		return storedUpload{}, fmt.Errorf("failed to prepare temporary file")
	}
	temporaryPath := destination.Name()
	defer os.Remove(temporaryPath)
	defer destination.Close()

	written, err := destination.Write(buffer)
	if err != nil {
		return storedUpload{}, fmt.Errorf("failed to prepare upload")
	}

	remainingLimit := maxBytes - int64(written)
	if remainingLimit < 0 {
		return storedUpload{}, fmt.Errorf("file is too large")
	}
	copied, err := io.Copy(destination, io.LimitReader(source, remainingLimit+1))
	if err != nil {
		return storedUpload{}, fmt.Errorf("failed to read upload")
	}
	totalSize := int64(written) + copied
	if totalSize > maxBytes {
		return storedUpload{}, fmt.Errorf("file is too large")
	}
	if err := destination.Sync(); err != nil {
		return storedUpload{}, fmt.Errorf("failed to finalize upload")
	}
	if _, err := destination.Seek(0, io.SeekStart); err != nil {
		return storedUpload{}, fmt.Errorf("failed to rewind upload")
	}
	if err := store.Put(ctx, relativePath, destination, totalSize, contentType); err != nil {
		cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if cleanupErr := store.Delete(cleanupCtx, relativePath); cleanupErr != nil {
			if queueErr := queueStorageDeletion(relativePath); queueErr != nil {
				slog.Error("partial_upload_cleanup_queue_failed", "error", queueErr)
			}
			slog.Error("upload_store_and_cleanup_failed", "error", err, "cleanup_error", cleanupErr)
			return storedUpload{}, errUploadStorage
		}
		// Storage errors can contain bucket names, endpoints or paths: log them
		// and give the client a generic message.
		slog.Error("upload_store_failed", "error", err)
		return storedUpload{}, errUploadStorage
	}

	return storedUpload{
		relativePath: relativePath,
		contentType:  contentType,
		sizeBytes:    totalSize,
	}, nil
}

// errUploadStorage marks a server-side storage failure, as opposed to a
// problem with the uploaded file itself.
var errUploadStorage = errors.New("failed to store file")

func writeUploadError(w http.ResponseWriter, err error) {
	if errors.Is(err, errUploadStorage) {
		Error(w, http.StatusServiceUnavailable, errUploadStorage.Error())
		return
	}
	Error(w, http.StatusBadRequest, err.Error())
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
