package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type ProjectDTO struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Address   string `json:"address,omitempty"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at,omitempty"`
}

type createProjectRequest struct {
	Name    string `json:"name"`
	Address string `json:"address"`
}

type updateProjectRequest struct {
	Name    string `json:"name"`
	Address string `json:"address"`
	Status  string `json:"status"`
}

func Projects(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	projectID := resourceIDFromPath(r.URL.Path, "/api/v1/projects/")
	if projectID != "" {
		switch r.Method {
		case http.MethodGet:
			getProject(w, r, projectID)
		case http.MethodPatch:
			updateProject(w, r, projectID)
		case http.MethodDelete:
			deleteProject(w, r, projectID)
		default:
			Error(w, http.StatusMethodNotAllowed, "method not allowed")
		}
		return
	}

	switch r.Method {
	case http.MethodGet:
		listProjects(w, r)
	case http.MethodPost:
		createProject(w, r)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listProjects(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	includeArchived, _ := strconv.ParseBool(r.URL.Query().Get("include_archived"))
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	rows, err := appState.DB.Pool.Query(ctx, `
		SELECT p.id::text, p.name, COALESCE(p.address, ''), p.status, p.created_at::text
		FROM projects p
		JOIN project_members pm ON pm.project_id = p.id
		WHERE pm.user_id = $1
		  AND p.deleted_at IS NULL
		  AND ($2 OR p.status = 'active')
		ORDER BY p.created_at DESC
	`, userID, includeArchived)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load projects")
		return
	}
	defer rows.Close()

	projects := []ProjectDTO{}
	for rows.Next() {
		var item ProjectDTO
		if err := rows.Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan project")
			return
		}
		projects = append(projects, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read projects")
		return
	}
	JSON(w, http.StatusOK, projects)
}

func getProject(w http.ResponseWriter, r *http.Request, projectID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item ProjectDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT id::text, name, COALESCE(address, ''), status, created_at::text
		FROM projects
		WHERE id = $1 AND deleted_at IS NULL
	`, projectID).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "project not found")
		return
	}
	JSON(w, http.StatusOK, item)
}

func createProject(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Address = strings.TrimSpace(req.Address)
	if req.Name == "" {
		Error(w, http.StatusBadRequest, "project name is required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start transaction")
		return
	}
	defer tx.Rollback(ctx)

	var item ProjectDTO
	err = tx.QueryRow(ctx, `
		INSERT INTO projects (owner_id, name, address)
		VALUES ($1, $2, NULLIF($3, ''))
		RETURNING id::text, name, COALESCE(address, ''), status, created_at::text
	`, userID, req.Name, req.Address).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create project")
		return
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role)
		VALUES ($1, $2, 'owner')
		ON CONFLICT DO NOTHING
	`, item.ID, userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create project membership")
		return
	}

	_, _ = tx.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'create', 'project', $2)
	`, userID, item.ID)

	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit project")
		return
	}

	JSON(w, http.StatusCreated, item)
}

func updateProject(w http.ResponseWriter, r *http.Request, projectID string) {
	userID := userIDFromContext(r.Context())
	var req updateProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Address = strings.TrimSpace(req.Address)
	req.Status = strings.TrimSpace(req.Status)
	if req.Name == "" {
		Error(w, http.StatusBadRequest, "project name is required")
		return
	}
	if req.Status == "" {
		req.Status = "active"
	}
	if req.Status != "active" && req.Status != "archived" {
		Error(w, http.StatusBadRequest, "invalid project status")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	var item ProjectDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		UPDATE projects
		SET name = $2, address = NULLIF($3, ''), status = $4, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id::text, name, COALESCE(address, ''), status, created_at::text
	`, projectID, req.Name, req.Address, req.Status).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "project not found")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'update', 'project', $2)
	`, userID, projectID)

	JSON(w, http.StatusOK, item)
}

func deleteProject(w http.ResponseWriter, r *http.Request, projectID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	result, err := appState.DB.Pool.Exec(ctx, `
		UPDATE projects
		SET status = 'archived', updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL AND status <> 'archived'
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to archive project")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "project not found or already archived")
		return
	}
	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'archive', 'project', $2)
	`, userID, projectID)
	JSON(w, http.StatusOK, map[string]string{"status": "archived"})
}
