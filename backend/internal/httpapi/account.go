package httpapi

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"
)

// DeleteAccount permanently removes the authenticated user's account and the
// data owned by that account. Shared project records are removed or
// anonymised according to their foreign-key policy; stored files uploaded by
// the user are removed after the database transaction commits.
func DeleteAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	userID := userIDFromContext(r.Context())
	if userID == "" {
		Error(w, http.StatusUnauthorized, "authentication required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start account deletion")
		return
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx, `
		SELECT DISTINCT f.storage_path
		FROM files f
		LEFT JOIN projects p ON p.id = f.project_id
		WHERE f.uploaded_by = $1 OR p.owner_id = $1
	`, userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to prepare account deletion")
		return
	}
	var storagePaths []string
	for rows.Next() {
		var storagePath string
		if err := rows.Scan(&storagePath); err != nil {
			rows.Close()
			Error(w, http.StatusInternalServerError, "failed to read account files")
			return
		}
		storagePaths = append(storagePaths, storagePath)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		Error(w, http.StatusInternalServerError, "failed to read account files")
		return
	}
	rows.Close()

	// uploaded_by uses ON DELETE SET NULL because a shared project may outlive
	// its uploader. Delete those file records explicitly for a complete account
	// deletion; owned-project records are removed by the user cascade below.
	if _, err := tx.Exec(ctx, `DELETE FROM files WHERE uploaded_by = $1`, userID); err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete account files")
		return
	}

	result, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete account")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "account not found")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to complete account deletion")
		return
	}

	for _, storagePath := range storagePaths {
		if err := removeStoredFile(storagePath); err != nil && !os.IsNotExist(err) {
			log.Printf(
				"request_id=%s failed_to_remove_account_file=%q error=%v",
				requestIDFromContext(r.Context()), storagePath, err,
			)
		}
	}

	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
