package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

type FileDTO struct {
	ID           string `json:"id"`
	ProjectID    string `json:"project_id,omitempty"`
	Kind         string `json:"kind"`
	OriginalName string `json:"original_name"`
	StoragePath  string `json:"storage_path"`
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
		SELECT id::text, COALESCE(project_id::text, ''), kind, original_name, storage_path, content_type, size_bytes, created_at::text
		FROM files
		WHERE project_id = $1
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
	if appState.MaxUploadBytes > 0 && req.SizeBytes > appState.MaxUploadBytes {
		Error(w, http.StatusBadRequest, "file is too large")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canContributeToProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item FileDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO files (project_id, uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id::text, COALESCE(project_id::text, ''), kind, original_name, storage_path, content_type, size_bytes, created_at::text
	`, req.ProjectID, userID, req.Kind, req.OriginalName, req.StoragePath, req.ContentType, req.SizeBytes).Scan(&item.ID, &item.ProjectID, &item.Kind, &item.OriginalName, &item.StoragePath, &item.ContentType, &item.SizeBytes, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save file metadata")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'upload', 'file', $3)
	`, userID, req.ProjectID, item.ID)

	JSON(w, http.StatusCreated, item)
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
	return kind == "receipt" || kind == "photo" || kind == "document"
}

func isSafeStoragePath(value string) bool {
	if value == "" || strings.HasPrefix(value, "/") || filepath.IsAbs(value) {
		return false
	}
	cleaned := filepath.ToSlash(filepath.Clean(value))
	return cleaned != "." && cleaned != ".." && !strings.HasPrefix(cleaned, "../") && !strings.Contains(cleaned, "/../")
}

func isAllowedFileType(contentType string) bool {
	switch contentType {
	case "image/jpeg", "image/png", "image/webp", "application/pdf":
		return true
	default:
		return false
	}
}
