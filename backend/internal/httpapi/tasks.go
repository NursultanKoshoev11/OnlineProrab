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

	taskID := resourceIDFromPath(r.URL.Path, "/api/v1/tasks/")
	if taskID != "" {
		switch r.Method {
		case http.MethodPatch:
			updateTask(w, r, taskID)
		case http.MethodDelete:
			deleteTask(w, r, taskID)
		default:
			Error(w, http.StatusMethodNotAllowed, "method not allowed")
		}
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
	if !isValidTaskStatus(req.Status) {
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

func updateTask(w http.ResponseWriter, r *http.Request, taskID string) {
	userID := userIDFromContext(r.Context())
	var req createTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.Title == "" {
		Error(w, http.StatusBadRequest, "title is required")
		return
	}
	if req.Status == "" {
		req.Status = "open"
	}
	if !isValidTaskStatus(req.Status) {
		Error(w, http.StatusBadRequest, "invalid task status")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := taskProjectID(ctx, taskID)
	if !ok || !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item TaskDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		UPDATE tasks
		SET title = $2, description = NULLIF($3, ''), status = $4, due_date = NULLIF($5, '')::date, updated_at = now()
		WHERE id = $1
		RETURNING id::text, project_id::text, title, COALESCE(description, ''), status, COALESCE(due_date::text, ''), created_at::text
	`, taskID, req.Title, req.Description, req.Status, req.DueDate).Scan(&item.ID, &item.ProjectID, &item.Title, &item.Description, &item.Status, &item.DueDate, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "task not found")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'update', 'task', $3)
	`, userID, projectID, taskID)

	JSON(w, http.StatusOK, item)
}

func deleteTask(w http.ResponseWriter, r *http.Request, taskID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := taskProjectID(ctx, taskID)
	if !ok || !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	result, err := appState.DB.Pool.Exec(ctx, `DELETE FROM tasks WHERE id = $1`, taskID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete task")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "task not found")
		return
	}
	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func taskProjectID(ctx context.Context, taskID string) (string, bool) {
	var projectID string
	err := appState.DB.Pool.QueryRow(ctx, `SELECT project_id::text FROM tasks WHERE id = $1`, taskID).Scan(&projectID)
	return projectID, err == nil
}

func isValidTaskStatus(status string) bool {
	return status == "open" || status == "in_progress" || status == "done"
}
