package httpapi

import (
	"context"
	"net/http"
	"time"
)

// DeleteAccount permanently removes the authenticated user's account and the
// data owned by that account. Shared project records are removed or
// anonymised according to their foreign-key policy; stored-file removals are
// recorded transactionally and processed by the storage deletion worker.
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

	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
