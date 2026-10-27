package httpapi

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"mime"
	"net/http"
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
	var storedSize int64
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text, original_name, storage_path, content_type, size_bytes
		FROM files
		WHERE id = $1 AND deleted_at IS NULL
	`, fileID).Scan(&projectID, &originalName, &storagePath, &contentType, &storedSize)
	if err != nil {
		Error(w, http.StatusNotFound, "file not found")
		return
	}

	userID := userIDFromContext(r.Context())
	if !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	if appState.FileStore == nil {
		Error(w, http.StatusServiceUnavailable, "file storage is not configured")
		return
	}
	object, err := appState.FileStore.Get(ctx, storagePath)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			Error(w, http.StatusNotFound, "stored file is unavailable")
			return
		}
		Error(w, http.StatusBadGateway, "failed to read stored file")
		return
	}
	if object.Body == nil || object.Size < 0 {
		if object.Body != nil {
			_ = object.Body.Close()
		}
		Error(w, http.StatusNotFound, "stored file is unavailable")
		return
	}
	defer object.Body.Close()
	if object.Size != storedSize {
		slog.Error("stored_file_size_mismatch", "request_id", requestIDFromContext(r.Context()), "file_id", fileID, "database_size", storedSize, "storage_size", object.Size)
		Error(w, http.StatusBadGateway, "stored file is unavailable")
		return
	}

	filename := sanitizeOriginalName(originalName)
	if filename == "" {
		filename = "download"
	}
	disposition := mime.FormatMediaType("attachment", map[string]string{"filename": filename})
	if disposition != "" {
		w.Header().Set("Content-Disposition", disposition)
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "private, no-store")
	if seeker, ok := object.Body.(io.ReadSeeker); ok {
		http.ServeContent(w, r, filename, object.ModTime, seeker)
		return
	}
	w.Header().Set("Accept-Ranges", "none")
	w.Header().Set("Content-Length", formatInt64(object.Size))
	if !object.ModTime.IsZero() {
		w.Header().Set("Last-Modified", object.ModTime.UTC().Format(http.TimeFormat))
	}
	if _, err := io.Copy(w, object.Body); err != nil {
		slog.Warn("stored_file_stream_interrupted", "request_id", requestIDFromContext(r.Context()), "file_id", fileID, "error", err)
	}
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
