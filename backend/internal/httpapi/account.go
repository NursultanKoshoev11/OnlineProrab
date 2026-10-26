package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
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
	if appState.IsProductionLike && appState.DeletionJournal == nil {
		Error(w, http.StatusServiceUnavailable, "account deletion protection is unavailable")
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

	var lockedUserID string
	if err := tx.QueryRow(ctx, `SELECT id::text FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&lockedUserID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			Error(w, http.StatusNotFound, "account not found")
			return
		}
		Error(w, http.StatusInternalServerError, "failed to lock account for deletion")
		return
	}

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
	if appState.DeletionJournal != nil {
		// Persist the deletion intent outside both the database and upload snapshots
		// before committing so a restore cannot silently resurrect this account.
		if err := appState.DeletionJournal.RecordAccountDeletion(ctx, lockedUserID); err != nil {
			Error(w, http.StatusServiceUnavailable, "could not secure account deletion")
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to complete account deletion")
		return
	}

	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
