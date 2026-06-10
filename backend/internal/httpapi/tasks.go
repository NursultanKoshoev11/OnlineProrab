package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

type TaskDTO struct {
	ID          string `json:"id"`
	ProjectID   string `json:"project_id"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Status      string `json:"status"`
	DueDate     string `json:"due_date,omitempty"`
	CreatedAt   string `json:"created_at,omitempty"`
}

type createTaskRequest struct {
	ProjectID   string `json:"project_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Status      string `json:"status"`
	DueDate     string `json:"due_date"`
}

func Tasks(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	switch r.Method {
	case http.MethodGet:
		listTasks(w, r)
	case http.MethodPost:
		createTask(w, r)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listTasks(w http.ResponseWriter, r *http.Request) {
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
		SELECT id::text, project_id::text, title, COALESCE(description, ''), status, COALESCE(due_date::text, ''), created_at::text
		FROM tasks
		WHERE project_id = $1
		ORDER BY created_at DESC
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load tasks")
		return
	}
	defer rows.Close()

	items := []TaskDTO{}
	for rows.Next() {
		var item TaskDTO
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.Title, &item.Description, &item.Status, &item.DueDate, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan task")
			return
		}
		items = append(items, item)
	}
	JSON(w, http.StatusOK, items)
}

func createTask(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.ProjectID == "" || req.Title == "" {
		Error(w, http.StatusBadRequest, "project_id and title are required")
		return
	}
	if req.Status == "" {
		req.Status = "open"
	}
	if req.Status != "open" && req.Status != "in_progress" && req.Status != "done" {
		Error(w, http.StatusBadRequest, "invalid task status")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item TaskDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO tasks (project_id, created_by, title, description, status, due_date)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, NULLIF($6, '')::date)
		RETURNING id::text, project_id::text, title, COALESCE(description, ''), status, COALESCE(due_date::text, ''), created_at::text
	`, req.ProjectID, userID, req.Title, req.Description, req.Status, req.DueDate).Scan(&item.ID, &item.ProjectID, &item.Title, &item.Description, &item.Status, &item.DueDate, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create task")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'create', 'task', $3)
	`, userID, req.ProjectID, item.ID)

	JSON(w, http.StatusCreated, item)
}
