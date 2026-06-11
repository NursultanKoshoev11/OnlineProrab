package httpapi

import (
	"context"
	"mime"
	"net/http"
	"os"
	"strings"
	"time"
)

func DownloadFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	fileID := strings.TrimSpace(r.URL.Query().Get("file_id"))
	if fileID == "" {
		Error(w, http.StatusBadRequest, "file_id is required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var projectID string
	var originalName string
	var storagePath string
	var contentType string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text, original_name, storage_path, content_type
		FROM files
		WHERE id = $1 AND deleted_at IS NULL
	`, fileID).Scan(&projectID, &originalName, &storagePath, &contentType)
	if err != nil {
		Error(w, http.StatusNotFound, "file not found")
		return
	}

	userID := userIDFromContext(r.Context())
	if !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	absolutePath, ok := resolveStoredFilePath(appState.UploadDir, storagePath)
	if !ok {
		Error(w, http.StatusNotFound, "stored file is unavailable")
		return
	}

	file, err := os.Open(absolutePath)
	if err != nil {
		if os.IsNotExist(err) {
			Error(w, http.StatusNotFound, "stored file is unavailable")
			return
		}
		Error(w, http.StatusInternalServerError, "failed to open stored file")
		return
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		Error(w, http.StatusNotFound, "stored file is unavailable")
		return
	}

	filename := sanitizeOriginalName(originalName)
	if filename == "" {
		filename = "download"
	}
	disposition, err := mime.FormatMediaType("attachment", map[string]string{"filename": filename})
	if err == nil {
		w.Header().Set("Content-Disposition", disposition)
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", formatInt64(info.Size()))
	w.Header().Set("Cache-Control", "private, no-store")
	http.ServeContent(w, r, filename, info.ModTime(), file)
}

func formatInt64(value int64) string {
	if value == 0 {
		return "0"
	}
	var buffer [20]byte
	position := len(buffer)
	for value > 0 {
		position--
		buffer[position] = byte('0' + value%10)
		value /= 10
	}
	return string(buffer[position:])
}
