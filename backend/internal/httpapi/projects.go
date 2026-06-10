package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
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

func Projects(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
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
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	rows, err := appState.DB.Pool.Query(ctx, `
		SELECT p.id::text, p.name, COALESCE(p.address, ''), p.status, p.created_at::text
		FROM projects p
		JOIN project_members pm ON pm.project_id = p.id
		WHERE pm.user_id = $1
		ORDER BY p.created_at DESC
	`, userID)
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
	JSON(w, http.StatusOK, projects)
}

func createProject(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
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
