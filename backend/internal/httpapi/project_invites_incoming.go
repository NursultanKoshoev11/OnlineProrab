package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/notifications"
)

// Joining a project is the invitee's decision: an invitation to a phone that
// already has an account stays pending until its owner accepts or declines it
// here. Without consent, any paying owner could attach arbitrary accounts to a
// project, learn their names from the member list and push them messages.

type incomingProjectInvite struct {
	ID          string `json:"id"`
	ProjectID   string `json:"project_id"`
	ProjectName string `json:"project_name"`
	Role        string `json:"role"`
	InvitedBy   string `json:"invited_by_name"`
	ExpiresAt   string `json:"expires_at"`
}

type incomingInviteDecisionRequest struct {
	InviteID string `json:"invite_id"`
}

// IncomingProjectInvites lists pending invitations addressed to the caller's
// phone number.
func IncomingProjectInvites(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	rows, err := appState.DB.Pool.Query(ctx, `
		SELECT i.id::text, i.project_id::text, p.name, i.role,
		       COALESCE(NULLIF(inviter.name, ''), ''), i.expires_at::text
		FROM users me
		JOIN project_invites i ON i.phone = me.phone
		JOIN projects p ON p.id = i.project_id AND p.deleted_at IS NULL
		LEFT JOIN users inviter ON inviter.id = i.invited_by
		WHERE me.id = $1
		  AND i.accepted_at IS NULL
		  AND i.revoked_at IS NULL
		  AND i.expires_at > now()
		  AND NOT EXISTS (
		      SELECT 1 FROM project_members pm
		      WHERE pm.project_id = i.project_id AND pm.user_id = me.id
		  )
		ORDER BY i.created_at DESC
		LIMIT 50
	`, userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load invitations")
		return
	}
	defer rows.Close()
	items := make([]incomingProjectInvite, 0)
	for rows.Next() {
		var item incomingProjectInvite
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.ProjectName, &item.Role, &item.InvitedBy, &item.ExpiresAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to read invitations")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read invitations")
		return
	}
	JSON(w, http.StatusOK, map[string]any{"items": items})
}

func decodeInviteDecision(w http.ResponseWriter, r *http.Request) (string, bool) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return "", false
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return "", false
	}
	var req incomingInviteDecisionRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return "", false
	}
	req.InviteID = strings.TrimSpace(req.InviteID)
	if !accountIDRe.MatchString(req.InviteID) {
		Error(w, http.StatusBadRequest, "valid invite_id is required")
		return "", false
	}
	return req.InviteID, true
}

// AcceptIncomingProjectInvite adds the caller to the project of a pending
// invitation addressed to their phone number.
func AcceptIncomingProjectInvite(w http.ResponseWriter, r *http.Request) {
	inviteID, ok := decodeInviteDecision(w, r)
	if !ok {
		return
	}
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start invitation acceptance")
		return
	}
	defer tx.Rollback(ctx)

	var projectID, phone, role string
	err = tx.QueryRow(ctx, `
		SELECT i.project_id::text, i.phone, i.role
		FROM project_invites i
		JOIN users me ON me.phone = i.phone
		JOIN projects p ON p.id = i.project_id AND p.deleted_at IS NULL
		WHERE i.id = $1 AND me.id = $2
		  AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now()
		FOR UPDATE OF i
	`, inviteID, userID).Scan(&projectID, &phone, &role)
	if err != nil {
		Error(w, http.StatusNotFound, "invitation not found or expired")
		return
	}
	if err := ensureProjectMemberCapacity(ctx, tx, projectID, phone); err != nil {
		if status, message, ok := subscriptionHTTPError(err); ok {
			Error(w, status, message)
			return
		}
		Error(w, http.StatusInternalServerError, "failed to enforce subscription limits")
		return
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role)
		VALUES ($1, $2, $3)
		ON CONFLICT (project_id, user_id) DO NOTHING
	`, projectID, userID, role); err != nil {
		Error(w, http.StatusInternalServerError, "failed to add project member")
		return
	}
	if _, err := tx.Exec(ctx, `UPDATE project_invites SET accepted_at = now() WHERE id = $1`, inviteID); err != nil {
		Error(w, http.StatusInternalServerError, "failed to complete invitation")
		return
	}
	bestEffortTxExec(ctx, tx, "audit_log", `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'accept_invite', 'project_member', $1, jsonb_build_object('role', $3::text, 'source', 'in_app'))
	`, userID, projectID, role)
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit invitation")
		return
	}
	publishProjectEvent(projectID, "project_member", userID, "accepted")
	JSON(w, http.StatusOK, map[string]string{"status": "accepted", "project_id": projectID, "role": role})
}

// DeclineIncomingProjectInvite closes a pending invitation addressed to the
// caller's phone number without joining the project.
func DeclineIncomingProjectInvite(w http.ResponseWriter, r *http.Request) {
	inviteID, ok := decodeInviteDecision(w, r)
	if !ok {
		return
	}
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	var projectID string
	err := appState.DB.Pool.QueryRow(ctx, `
		UPDATE project_invites i
		SET revoked_at = now()
		FROM users me
		WHERE i.id = $1 AND me.id = $2 AND me.phone = i.phone
		  AND i.accepted_at IS NULL AND i.revoked_at IS NULL
		RETURNING i.project_id::text
	`, inviteID, userID).Scan(&projectID)
	if err != nil {
		Error(w, http.StatusNotFound, "invitation not found")
		return
	}
	publishProjectEvent(projectID, "project_member", "", "declined")
	JSON(w, http.StatusOK, map[string]string{"status": "declined"})
}

// notifyInvitedAccount tells an existing account about a new invitation. It
// runs in the background so push latency never slows down the inviter.
func notifyInvitedAccount(phone, projectID, inviterID string) {
	if appState.PushSender == nil || appState.DB == nil || appState.DB.Pool == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		var projectName, inviterName string
		if err := appState.DB.Pool.QueryRow(ctx, `
			SELECT p.name, COALESCE(NULLIF(u.name, ''), '')
			FROM projects p LEFT JOIN users u ON u.id = $2
			WHERE p.id = $1
		`, projectID, inviterID).Scan(&projectName, &inviterName); err != nil {
			return
		}
		rows, err := appState.DB.Pool.Query(ctx, `
			SELECT t.token, t.target_type
			FROM push_tokens t JOIN users u ON u.id = t.user_id
			WHERE u.phone = $1
		`, phone)
		if err != nil {
			slog.Error("push_token_lookup_failed", "project_id", projectID, "error", err)
			return
		}
		targets := make([]notifications.Target, 0)
		for rows.Next() {
			var target notifications.Target
			if rows.Scan(&target.ID, &target.Type) == nil {
				targets = append(targets, target)
			}
		}
		rows.Close()
		if len(targets) == 0 {
			return
		}
		body := "Вас приглашают в объект «" + sanitizeNotificationText(projectName, "Объект") + "»"
		if inviterName != "" {
			body = sanitizeNotificationText(inviterName, "Пользователь") + " приглашает вас в объект «" + sanitizeNotificationText(projectName, "Объект") + "»"
		}
		err = appState.PushSender.Send(ctx, targets, "Приглашение в объект", body, map[string]string{
			"type":       "project_invite",
			"project_id": projectID,
		})
		var sendErr *notifications.SendError
		if errors.As(err, &sendErr) {
			forgetUnregisteredPushTargets(sendErr.Unregistered)
		}
		if err != nil {
			slog.Warn("project_invite_push_failed", "project_id", projectID, "error", err)
		}
	}()
}
