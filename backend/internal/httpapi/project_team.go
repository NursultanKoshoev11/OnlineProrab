package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

const projectInviteTTL = 7 * 24 * time.Hour

type ProjectMemberDTO struct {
	UserID    string `json:"user_id"`
	Phone     string `json:"phone,omitempty"`
	Name      string `json:"name,omitempty"`
	Role      string `json:"role"`
	CreatedAt string `json:"created_at"`
}

type createProjectInviteRequest struct {
	ProjectID string `json:"project_id"`
	Phone     string `json:"phone"`
	Role      string `json:"role"`
}

type acceptProjectInviteRequest struct {
	InviteToken string `json:"invite_token"`
}

type updateProjectMemberRequest struct {
	Role string `json:"role"`
}

func ProjectMembers(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	projectID := strings.TrimSpace(r.URL.Query().Get("project_id"))
	if projectID == "" {
		Error(w, http.StatusBadRequest, "project_id is required")
		return
	}
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	rows, err := appState.DB.Pool.Query(ctx, `
		SELECT u.id::text, COALESCE(u.phone, ''), COALESCE(u.name, ''), pm.role, pm.created_at::text
		FROM project_members pm
		JOIN users u ON u.id = pm.user_id
		WHERE pm.project_id = $1
		ORDER BY CASE pm.role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 WHEN 'worker' THEN 2 ELSE 3 END, pm.created_at
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load project members")
		return
	}
	defer rows.Close()

	items := []ProjectMemberDTO{}
	for rows.Next() {
		var item ProjectMemberDTO
		if err := rows.Scan(&item.UserID, &item.Phone, &item.Name, &item.Role, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan project member")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read project members")
		return
	}
	JSON(w, http.StatusOK, map[string]any{"items": items})
}

func CreateProjectInvite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req createProjectInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.ProjectID = strings.TrimSpace(req.ProjectID)
	req.Phone = normalizePhone(req.Phone)
	req.Role = strings.ToLower(strings.TrimSpace(req.Role))
	if req.ProjectID == "" || !phoneRe.MatchString(req.Phone) || !isAssignableProjectRole(req.Role) {
		Error(w, http.StatusBadRequest, "project_id, valid phone and role are required")
		return
	}

	actorID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	if !canManageProject(ctx, actorID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	var exists bool
	if err := appState.DB.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM project_members pm
			JOIN users u ON u.id = pm.user_id
			WHERE pm.project_id = $1 AND u.phone = $2
		)
	`, req.ProjectID, req.Phone).Scan(&exists); err != nil {
		Error(w, http.StatusInternalServerError, "failed to check project membership")
		return
	}
	if exists {
		Error(w, http.StatusConflict, "user is already a project member")
		return
	}

	token, err := newProjectInviteToken()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create invitation")
		return
	}
	_, err = appState.DB.Pool.Exec(ctx, `
		UPDATE project_invites
		SET revoked_at = now()
		WHERE project_id = $1 AND phone = $2 AND accepted_at IS NULL AND revoked_at IS NULL
	`, req.ProjectID, req.Phone)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to replace previous invitation")
		return
	}
	_, err = appState.DB.Pool.Exec(ctx, `
		INSERT INTO project_invites (project_id, invited_by, phone, role, token_hash, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, req.ProjectID, actorID, req.Phone, req.Role, hashProjectInviteToken(token), time.Now().UTC().Add(projectInviteTTL))
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save invitation")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, metadata)
		VALUES ($1, $2, 'invite', 'project_member', jsonb_build_object('phone', $3, 'role', $4))
	`, actorID, req.ProjectID, req.Phone, req.Role)

	response := map[string]any{
		"status":     "invited",
		"expires_in": int64(projectInviteTTL.Seconds()),
	}
	if !appState.IsProduction {
		response["invite_token"] = token
	}
	JSON(w, http.StatusCreated, response)
}

func AcceptProjectInvite(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req acceptProjectInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.InviteToken = strings.TrimSpace(req.InviteToken)
	if req.InviteToken == "" {
		Error(w, http.StatusBadRequest, "invite_token is required")
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

	var projectID string
	var phone string
	var role string
	var inviteID string
	err = tx.QueryRow(ctx, `
		SELECT id::text, project_id::text, phone, role
		FROM project_invites
		WHERE token_hash = $1 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
		FOR UPDATE
	`, hashProjectInviteToken(req.InviteToken)).Scan(&inviteID, &projectID, &phone, &role)
	if err != nil {
		Error(w, http.StatusUnauthorized, "invalid or expired invitation")
		return
	}

	var userPhone string
	if err := tx.QueryRow(ctx, `SELECT COALESCE(phone, '') FROM users WHERE id = $1`, userID).Scan(&userPhone); err != nil {
		Error(w, http.StatusUnauthorized, "user not found")
		return
	}
	if normalizePhone(userPhone) != normalizePhone(phone) {
		Error(w, http.StatusForbidden, "invitation belongs to another phone number")
		return
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role)
		VALUES ($1, $2, $3)
		ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role
	`, projectID, userID, role)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to add project member")
		return
	}
	_, err = tx.Exec(ctx, `UPDATE project_invites SET accepted_at = now() WHERE id = $1`, inviteID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to complete invitation")
		return
	}
	_, _ = tx.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'accept_invite', 'project_member', $1, jsonb_build_object('role', $3))
	`, userID, projectID, role)
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit invitation")
		return
	}
	JSON(w, http.StatusOK, map[string]string{"status": "accepted", "project_id": projectID, "role": role})
}

func ProjectMember(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	projectID := strings.TrimSpace(r.URL.Query().Get("project_id"))
	memberID := resourceIDFromPath(r.URL.Path, "/api/v1/project-members/")
	if projectID == "" || memberID == "" {
		Error(w, http.StatusBadRequest, "project_id and member id are required")
		return
	}

	actorID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	if !canManageProject(ctx, actorID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	var currentRole string
	if err := appState.DB.Pool.QueryRow(ctx, `SELECT role FROM project_members WHERE project_id = $1 AND user_id = $2`, projectID, memberID).Scan(&currentRole); err != nil {
		Error(w, http.StatusNotFound, "project member not found")
		return
	}
	if currentRole == ProjectRoleOwner {
		Error(w, http.StatusConflict, "project owner cannot be modified or removed")
		return
	}

	switch r.Method {
	case http.MethodPatch:
		var req updateProjectMemberRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			Error(w, http.StatusBadRequest, "invalid JSON body")
			return
		}
		req.Role = strings.ToLower(strings.TrimSpace(req.Role))
		if !isAssignableProjectRole(req.Role) {
			Error(w, http.StatusBadRequest, "invalid project role")
			return
		}
		_, err := appState.DB.Pool.Exec(ctx, `UPDATE project_members SET role = $3 WHERE project_id = $1 AND user_id = $2`, projectID, memberID, req.Role)
		if err != nil {
			Error(w, http.StatusInternalServerError, "failed to update project member")
			return
		}
		_, _ = appState.DB.Pool.Exec(ctx, `
			INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
			VALUES ($1, $2, 'update_role', 'project_member', $3, jsonb_build_object('role', $4))
		`, actorID, projectID, memberID, req.Role)
		JSON(w, http.StatusOK, map[string]string{"status": "updated", "role": req.Role})
	case http.MethodDelete:
		result, err := appState.DB.Pool.Exec(ctx, `DELETE FROM project_members WHERE project_id = $1 AND user_id = $2`, projectID, memberID)
		if err != nil {
			Error(w, http.StatusInternalServerError, "failed to remove project member")
			return
		}
		if result.RowsAffected() == 0 {
			Error(w, http.StatusNotFound, "project member not found")
			return
		}
		_, _ = appState.DB.Pool.Exec(ctx, `
			INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
			VALUES ($1, $2, 'remove', 'project_member', $3)
		`, actorID, projectID, memberID)
		JSON(w, http.StatusOK, map[string]string{"status": "removed"})
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func isAssignableProjectRole(role string) bool {
	return role == ProjectRoleManager || role == ProjectRoleWorker || role == ProjectRoleViewer
}

func newProjectInviteToken() (string, error) {
	buffer := make([]byte, 32)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buffer), nil
}

func hashProjectInviteToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
