package httpapi

import (
	"context"
	"net/http"
	"time"
)

type AuditLogDTO struct {
	ID         string `json:"id"`
	ProjectID  string `json:"project_id,omitempty"`
	Action     string `json:"action"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id,omitempty"`
	CreatedAt  string `json:"created_at"`
}

func AuditLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	userID := userIDFromContext(r.Context())
	projectID := r.URL.Query().Get("project_id")
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
		SELECT id::text, COALESCE(project_id::text, ''), action, entity_type, COALESCE(entity_id::text, ''), created_at::text
		FROM audit_logs
		WHERE project_id = $1
		ORDER BY created_at DESC
		LIMIT 100
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load audit logs")
		return
	}
	defer rows.Close()

	items := []AuditLogDTO{}
	for rows.Next() {
		var item AuditLogDTO
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.Action, &item.EntityType, &item.EntityID, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan audit log")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read audit logs")
		return
	}
	JSON(w, http.StatusOK, items)
}
