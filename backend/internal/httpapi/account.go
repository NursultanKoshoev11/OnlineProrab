package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// DeleteAccount permanently removes the authenticated user's account.
// Projects the user owns that still have other members are handed over to a
// successor (the longest-standing manager, else worker, else viewer) so the
// team keeps its data; projects without other members are deleted with the
// account. Records the user created in shared projects stay and lose their
// author (ON DELETE SET NULL). Stored-file removals are recorded
// transactionally and processed by the storage deletion worker.
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

	transferred, err := transferOwnedSharedProjects(ctx, tx, userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to hand over shared projects")
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
	for _, handover := range transferred {
		publishProjectEvent(handover.projectID, "project_member", handover.newOwnerID, "owner_transferred")
	}

	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

type projectHandover struct {
	projectID  string
	newOwnerID string
}

// transferOwnedSharedProjects makes another member the owner of every live
// project the leaving user owns, preferring managers, then workers, then
// viewers, and the earliest member within a role.
func transferOwnedSharedProjects(ctx context.Context, tx pgx.Tx, userID string) ([]projectHandover, error) {
	rows, err := tx.Query(ctx, `
		WITH successors AS (
			SELECT DISTINCT ON (pm.project_id) pm.project_id, pm.user_id
			FROM project_members pm
			JOIN projects p ON p.id = pm.project_id
			WHERE p.owner_id = $1
			  AND p.deleted_at IS NULL
			  AND pm.user_id <> $1
			ORDER BY pm.project_id,
			         CASE pm.role WHEN 'manager' THEN 0 WHEN 'worker' THEN 1 ELSE 2 END,
			         pm.created_at,
			         pm.user_id
		),
		moved AS (
			UPDATE projects p
			SET owner_id = s.user_id, updated_at = now()
			FROM successors s
			WHERE p.id = s.project_id
			RETURNING p.id AS project_id, s.user_id
		)
		UPDATE project_members pm
		SET role = 'owner'
		FROM moved m
		WHERE pm.project_id = m.project_id AND pm.user_id = m.user_id
		RETURNING pm.project_id::text, pm.user_id::text
	`, userID)
	if err != nil {
		return nil, err
	}
	var handovers []projectHandover
	for rows.Next() {
		var item projectHandover
		if err := rows.Scan(&item.projectID, &item.newOwnerID); err != nil {
			rows.Close()
			return nil, err
		}
		handovers = append(handovers, item)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, item := range handovers {
		bestEffortTxExec(ctx, tx, "owner_transfer_audit_log", `
			INSERT INTO audit_logs (project_id, action, entity_type, entity_id, metadata)
			VALUES ($1, 'transfer_owner', 'project', $1, jsonb_build_object('new_owner_id', $2::text, 'reason', 'account_deleted'))
		`, item.projectID, item.newOwnerID)
	}
	return handovers, nil
}
