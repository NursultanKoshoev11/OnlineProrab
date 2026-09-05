package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type ProjectDTO struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Address     string `json:"address,omitempty"`
	Status      string `json:"status"`
	CoverFileID string `json:"cover_file_id,omitempty"`
	StartDate   string `json:"start_date"`
	CreatedAt   string `json:"created_at,omitempty"`
}

type createProjectRequest struct {
	Name      string `json:"name"`
	Address   string `json:"address"`
	StartDate string `json:"start_date"`
}

type updateProjectRequest struct {
	Name      string `json:"name"`
	Address   string `json:"address"`
	Status    string `json:"status"`
	StartDate string `json:"start_date"`
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
		SELECT p.id::text, p.name, COALESCE(p.address, ''), p.status,
		       COALESCE((
		           SELECT f.id::text
		           FROM files f
		           WHERE f.project_id = p.id
		             AND f.deleted_at IS NULL
		             AND f.kind = 'project_cover'
		             AND f.content_type LIKE 'image/%'
		           ORDER BY f.created_at DESC
		           LIMIT 1
		       ), ''),
		       p.start_date::text,
		       p.created_at::text
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
		if err := rows.Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CoverFileID, &item.StartDate, &item.CreatedAt); err != nil {
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
		SELECT p.id::text, p.name, COALESCE(p.address, ''), p.status,
		       COALESCE((
		           SELECT f.id::text
		           FROM files f
		           WHERE f.project_id = p.id
		             AND f.deleted_at IS NULL
		             AND f.kind = 'project_cover'
		             AND f.content_type LIKE 'image/%'
		           ORDER BY f.created_at DESC
		           LIMIT 1
		       ), ''),
		       p.start_date::text,
		       p.created_at::text
		FROM projects p
		WHERE p.id = $1 AND p.deleted_at IS NULL
	`, projectID).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.CoverFileID, &item.StartDate, &item.CreatedAt)
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
	startDate, err := normalizeProjectStartDate(req.StartDate, true)
	if err != nil {
		Error(w, http.StatusBadRequest, err.Error())
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
		INSERT INTO projects (owner_id, name, address, start_date)
		VALUES ($1, $2, NULLIF($3, ''), $4::date)
		RETURNING id::text, name, COALESCE(address, ''), status, start_date::text, created_at::text
	`, userID, req.Name, req.Address, startDate).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.StartDate, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create project")
		return
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role)
		VALUES ($1, $2, 'owner')
		ON CONFLICT DO NOTHING
	`, item.ID, userID); err != nil {
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

func CreateProjectWithCover(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	if strings.TrimSpace(appState.UploadDir) == "" {
		Error(w, http.StatusServiceUnavailable, "file storage is not configured")
		return
	}

	maxBytes := appState.MaxUploadBytes
	if maxBytes <= 0 {
		maxBytes = 10 * 1024 * 1024
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes+uploadMultipartOverhead)
	if err := r.ParseMultipartForm(maxBytes + uploadMultipartOverhead); err != nil {
		Error(w, http.StatusBadRequest, "invalid multipart upload or file too large")
		return
	}

	name := strings.TrimSpace(r.FormValue("name"))
	address := strings.TrimSpace(r.FormValue("address"))
	if name == "" {
		Error(w, http.StatusBadRequest, "project name is required")
		return
	}
	startDate, err := normalizeProjectStartDate(r.FormValue("start_date"), true)
	if err != nil {
		Error(w, http.StatusBadRequest, err.Error())
		return
	}

	source, header, err := r.FormFile("cover")
	if err != nil {
		Error(w, http.StatusBadRequest, "cover image is required")
		return
	}
	defer source.Close()
	originalName := sanitizeOriginalName(header.Filename)
	if originalName == "" {
		Error(w, http.StatusBadRequest, "invalid cover image name")
		return
	}

	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start transaction")
		return
	}
	defer tx.Rollback(ctx)

	var item ProjectDTO
	err = tx.QueryRow(ctx, `
		INSERT INTO projects (owner_id, name, address, start_date)
		VALUES ($1, $2, NULLIF($3, ''), $4::date)
		RETURNING id::text, name, COALESCE(address, ''), status, start_date::text, created_at::text
	`, userID, name, address, startDate).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.StartDate, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create project")
		return
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role)
		VALUES ($1, $2, 'owner')
		ON CONFLICT DO NOTHING
	`, item.ID, userID); err != nil {
		Error(w, http.StatusInternalServerError, "failed to create project membership")
		return
	}
	_, _ = tx.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'create', 'project', $2)
	`, userID, item.ID)

	stored, err := storeUploadedFile(source, header, item.ID, maxBytes)
	if err != nil {
		Error(w, http.StatusBadRequest, err.Error())
		return
	}
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(stored.absolutePath)
		}
	}()

	err = tx.QueryRow(ctx, `
		INSERT INTO files (project_id, uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
		VALUES ($1, $2, 'project_cover', $3, $4, $5, $6)
		RETURNING id::text
	`, item.ID, userID, originalName, stored.relativePath, stored.contentType, stored.sizeBytes).Scan(&item.CoverFileID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save project cover")
		return
	}

	_, _ = tx.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'upload', 'file', $3, jsonb_build_object('kind', 'project_cover'))
	`, userID, item.ID, item.CoverFileID)

	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit project")
		return
	}
	cleanup = false
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
	startDate, err := normalizeProjectStartDate(req.StartDate, false)
	if err != nil {
		Error(w, http.StatusBadRequest, err.Error())
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	var item ProjectDTO
	err = appState.DB.Pool.QueryRow(ctx, `
		UPDATE projects
		SET name = $2,
		    address = NULLIF($3, ''),
		    status = $4,
		    start_date = COALESCE(NULLIF($5, '')::date, start_date),
		    updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id::text, name, COALESCE(address, ''), status, start_date::text, created_at::text
	`, projectID, req.Name, req.Address, req.Status, startDate).Scan(&item.ID, &item.Name, &item.Address, &item.Status, &item.StartDate, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "project not found")
		return
	}

	_ = appState.DB.Pool.QueryRow(ctx, `
		SELECT COALESCE((
			SELECT f.id::text FROM files f
			WHERE f.project_id = $1 AND f.deleted_at IS NULL
			  AND f.kind = 'project_cover' AND f.content_type LIKE 'image/%'
			ORDER BY f.created_at DESC LIMIT 1
		), '')
	`, projectID).Scan(&item.CoverFileID)

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

func normalizeProjectStartDate(raw string, fallbackToday bool) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		if fallbackToday {
			return time.Now().Format("2006-01-02"), nil
		}
		return "", nil
	}
	if _, err := time.Parse("2006-01-02", value); err != nil {
		return "", fmt.Errorf("start_date must use YYYY-MM-DD format")
	}
	return value, nil
}
