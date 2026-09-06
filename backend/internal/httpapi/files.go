package httpapi

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type FileDTO struct {
	ID           string `json:"id"`
	ProjectID    string `json:"project_id,omitempty"`
	Kind         string `json:"kind"`
	OriginalName string `json:"original_name"`
	StoragePath  string `json:"-"`
	ContentType  string `json:"content_type"`
	SizeBytes    int64  `json:"size_bytes"`
	CreatedAt    string `json:"created_at,omitempty"`
}

type createFileRequest struct {
	ProjectID    string `json:"project_id"`
	Kind         string `json:"kind"`
	OriginalName string `json:"original_name"`
	StoragePath  string `json:"storage_path"`
	ContentType  string `json:"content_type"`
	SizeBytes    int64  `json:"size_bytes"`
}

func Files(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	fileID := resourceIDFromPath(r.URL.Path, "/api/v1/files/")
	if fileID != "" {
		switch r.Method {
		case http.MethodDelete:
			deleteFileMetadata(w, r, fileID)
		default:
			Error(w, http.StatusMethodNotAllowed, "method not allowed")
		}
		return
	}

	switch r.Method {
	case http.MethodGet:
		listFiles(w, r)
	case http.MethodPost:
		createFileMetadata(w, r)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listFiles(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	projectID := strings.TrimSpace(r.URL.Query().Get("project_id"))
	if projectID == "" {
		Error(w, http.StatusBadRequest, "project_id is required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	rows, err := appState.DB.Pool.Query(ctx, `
		SELECT id::text, COALESCE(project_id::text, ''), kind, original_name,
		       storage_path, content_type, size_bytes, created_at::text
		FROM files
		WHERE project_id = $1 AND deleted_at IS NULL
		ORDER BY created_at DESC
		LIMIT 500
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load files")
		return
	}
	defer rows.Close()

	items := []FileDTO{}
	for rows.Next() {
		var item FileDTO
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.Kind, &item.OriginalName, &item.StoragePath, &item.ContentType, &item.SizeBytes, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan file")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read files")
		return
	}
	JSON(w, http.StatusOK, map[string]any{"items": items})
}

func createFileMetadata(w http.ResponseWriter, r *http.Request) {
	if appState.IsProduction {
		Error(w, http.StatusForbidden, "direct file metadata creation is disabled; use the upload endpoint")
		return
	}

	userID := userIDFromContext(r.Context())
	var req createFileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	normalizeFileRequest(&req)
	if req.ProjectID == "" || req.OriginalName == "" || req.StoragePath == "" || req.ContentType == "" || req.SizeBytes < 0 {
		Error(w, http.StatusBadRequest, "project_id, original_name, storage_path, content_type and non-negative size_bytes are required")
		return
	}
	if len(req.OriginalName) > 255 || len(req.StoragePath) > 512 {
		Error(w, http.StatusBadRequest, "file name or storage path is too long")
		return
	}
	if !isValidFileKind(req.Kind) {
		Error(w, http.StatusBadRequest, "invalid file kind")
		return
	}
	if !isSafeStoragePath(req.StoragePath) {
		Error(w, http.StatusBadRequest, "invalid storage path")
		return
	}
	if !isAllowedFileType(req.ContentType) {
		Error(w, http.StatusBadRequest, "unsupported file type")
		return
	}
	if req.Kind == "project_cover" && !isAllowedProjectCoverType(req.ContentType) {
		Error(w, http.StatusBadRequest, "project cover must be a JPEG, PNG or WebP image")
		return
	}
	if appState.MaxUploadBytes > 0 && req.SizeBytes > appState.MaxUploadBytes {
		Error(w, http.StatusBadRequest, "file is too large")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if req.Kind == "project_cover" && !canManageProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}
	if !canContributeToProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item FileDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO files (project_id, uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id::text, COALESCE(project_id::text, ''), kind, original_name,
		          storage_path, content_type, size_bytes, created_at::text
	`, req.ProjectID, userID, req.Kind, req.OriginalName, req.StoragePath, req.ContentType, req.SizeBytes).Scan(&item.ID, &item.ProjectID, &item.Kind, &item.OriginalName, &item.StoragePath, &item.ContentType, &item.SizeBytes, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save file metadata")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'upload', 'file', $3)
	`, userID, req.ProjectID, item.ID)
	if req.Kind == "project_cover" {
		archivePreviousProjectCovers(ctx, req.ProjectID, item.ID)
	}

	JSON(w, http.StatusCreated, item)
}

func deleteFileMetadata(w http.ResponseWriter, r *http.Request, fileID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var projectID string
	var storagePath string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text, storage_path
		FROM files
		WHERE id = $1 AND deleted_at IS NULL
	`, fileID).Scan(&projectID, &storagePath)
	if err != nil {
		Error(w, http.StatusNotFound, "file not found")
		return
	}
	if !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start file deletion")
		return
	}
	defer tx.Rollback(ctx)

	result, err := tx.Exec(ctx, `
		UPDATE files
		SET deleted_at = now()
		WHERE id = $1 AND deleted_at IS NULL
	`, fileID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete file metadata")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "file not found")
		return
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cost_items
		SET receipt_file_id = NULL, updated_at = now()
		WHERE receipt_file_id = $1 AND deleted_at IS NULL
	`, fileID); err != nil {
		Error(w, http.StatusInternalServerError, "failed to detach file from cost items")
		return
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'delete', 'file', $3, jsonb_build_object('storage_path', $4))
	`, userID, projectID, fileID, storagePath); err != nil {
		Error(w, http.StatusInternalServerError, "failed to record file deletion")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit file deletion")
		return
	}

	if err := removeStoredFile(storagePath); err != nil && !os.IsNotExist(err) {
		log.Printf("request_id=%s failed_to_remove_file=%q error=%v", requestIDFromContext(r.Context()), storagePath, err)
	}
	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func archivePreviousProjectCovers(ctx context.Context, projectID, currentFileID string) {
	rows, err := appState.DB.Pool.Query(ctx, `
		UPDATE files
		SET deleted_at = now()
		WHERE project_id = $1
		  AND kind = 'project_cover'
		  AND deleted_at IS NULL
		  AND id <> $2
		  AND created_at < (SELECT created_at FROM files WHERE id = $2)
		RETURNING storage_path
	`, projectID, currentFileID)
	if err != nil {
		log.Printf("request_id=%s failed_to_archive_previous_covers project_id=%q error=%v", requestIDFromContext(ctx), projectID, err)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var storagePath string
		if err := rows.Scan(&storagePath); err != nil {
			log.Printf("request_id=%s failed_to_read_archived_cover project_id=%q error=%v", requestIDFromContext(ctx), projectID, err)
			continue
		}
		if err := removeStoredFile(storagePath); err != nil && !os.IsNotExist(err) {
			log.Printf("request_id=%s failed_to_remove_previous_cover=%q error=%v", requestIDFromContext(ctx), storagePath, err)
		}
	}
	if err := rows.Err(); err != nil {
		log.Printf("request_id=%s failed_to_archive_previous_covers project_id=%q error=%v", requestIDFromContext(ctx), projectID, err)
	}
}

func removeStoredFile(storagePath string) error {
	absolutePath, ok := resolveStoredFilePath(appState.UploadDir, storagePath)
	if !ok {
		return os.ErrPermission
	}
	return os.Remove(absolutePath)
}

func resolveStoredFilePath(root, storagePath string) (string, bool) {
	root = filepath.Clean(strings.TrimSpace(root))
	storagePath = strings.ReplaceAll(strings.TrimSpace(storagePath), "\\", "/")
	storagePath = filepath.ToSlash(storagePath)
	if root == "" || root == "." || !isSafeStoragePath(storagePath) {
		return "", false
	}
	absolutePath := filepath.Clean(filepath.Join(root, filepath.FromSlash(storagePath)))
	relative, err := filepath.Rel(root, absolutePath)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", false
	}
	return absolutePath, true
}

func fileProjectID(ctx context.Context, fileID string) (string, bool) {
	var projectID string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text
		FROM files
		WHERE id = $1 AND deleted_at IS NULL
	`, fileID).Scan(&projectID)
	return projectID, err == nil
}

func normalizeFileRequest(req *createFileRequest) {
	req.ProjectID = strings.TrimSpace(req.ProjectID)
	req.Kind = strings.ToLower(strings.TrimSpace(req.Kind))
	req.OriginalName = strings.TrimSpace(req.OriginalName)
	req.StoragePath = strings.TrimSpace(strings.ReplaceAll(req.StoragePath, "\\", "/"))
	req.ContentType = strings.ToLower(strings.TrimSpace(req.ContentType))
	if req.Kind == "" {
		req.Kind = "document"
	}
}

func isValidFileKind(kind string) bool {
	return kind == "receipt" || kind == "photo" || kind == "document" || kind == "project_cover"
}

func isSafeStoragePath(value string) bool {
	value = strings.ReplaceAll(strings.TrimSpace(value), "\\", "/")
	if value == "" || strings.HasPrefix(value, "/") || filepath.IsAbs(filepath.FromSlash(value)) {
		return false
	}
	if len(value) >= 2 && isASCIIAlpha(value[0]) && value[1] == ':' {
		return false
	}
	for _, part := range strings.Split(value, "/") {
		if part == ".." {
			return false
		}
	}
	cleaned := filepath.ToSlash(filepath.Clean(filepath.FromSlash(value)))
	return cleaned != "." && cleaned != ".." && !strings.HasPrefix(cleaned, "../") && !strings.Contains(cleaned, "/../")
}

func isASCIIAlpha(value byte) bool {
	return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z')
}

func isAllowedFileType(contentType string) bool {
	switch contentType {
	case "image/jpeg", "image/png", "image/webp", "application/pdf":
		return true
	default:
		return false
	}
}

func isAllowedProjectCoverType(contentType string) bool {
	switch contentType {
	case "image/jpeg", "image/png", "image/webp":
		return true
	default:
		return false
	}
}
