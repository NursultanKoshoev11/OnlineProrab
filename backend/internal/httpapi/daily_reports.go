package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

type DailyReportDTO struct {
	ID           string `json:"id"`
	ProjectID    string `json:"project_id"`
	ReportDate   string `json:"report_date"`
	Summary      string `json:"summary"`
	WorkersCount int    `json:"workers_count"`
	Issues       string `json:"issues,omitempty"`
	CreatedAt    string `json:"created_at,omitempty"`
}

type createDailyReportRequest struct {
	ProjectID    string `json:"project_id"`
	ReportDate   string `json:"report_date"`
	Summary      string `json:"summary"`
	WorkersCount int    `json:"workers_count"`
	Issues       string `json:"issues"`
}

func DailyReports(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	reportID := resourceIDFromPath(r.URL.Path, "/api/v1/daily-reports/")
	if reportID != "" {
		switch r.Method {
		case http.MethodGet:
			getDailyReport(w, r, reportID)
		case http.MethodPatch:
			updateDailyReport(w, r, reportID)
		case http.MethodDelete:
			deleteDailyReport(w, r, reportID)
		default:
			Error(w, http.StatusMethodNotAllowed, "method not allowed")
		}
		return
	}

	switch r.Method {
	case http.MethodGet:
		listDailyReports(w, r)
	case http.MethodPost:
		createDailyReport(w, r)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listDailyReports(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	projectID := strings.TrimSpace(r.URL.Query().Get("project_id"))
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
		SELECT id::text, project_id::text, report_date::text, summary, workers_count,
		       COALESCE(issues, ''), created_at::text
		FROM daily_reports
		WHERE project_id = $1 AND deleted_at IS NULL
		ORDER BY report_date DESC, created_at DESC
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load daily reports")
		return
	}
	defer rows.Close()

	items := []DailyReportDTO{}
	for rows.Next() {
		var item DailyReportDTO
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.ReportDate, &item.Summary, &item.WorkersCount, &item.Issues, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan daily report")
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read daily reports")
		return
	}
	JSON(w, http.StatusOK, items)
}

func getDailyReport(w http.ResponseWriter, r *http.Request, reportID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := dailyReportProjectID(ctx, reportID)
	if !ok || !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item DailyReportDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT id::text, project_id::text, report_date::text, summary, workers_count,
		       COALESCE(issues, ''), created_at::text
		FROM daily_reports
		WHERE id = $1 AND deleted_at IS NULL
	`, reportID).Scan(&item.ID, &item.ProjectID, &item.ReportDate, &item.Summary, &item.WorkersCount, &item.Issues, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "daily report not found")
		return
	}
	JSON(w, http.StatusOK, item)
}

func createDailyReport(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createDailyReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	normalizeDailyReportRequest(&req)
	if req.ProjectID == "" || req.Summary == "" || req.WorkersCount < 0 {
		Error(w, http.StatusBadRequest, "project_id, summary and non-negative workers_count are required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canContributeToProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item DailyReportDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO daily_reports (project_id, created_by, report_date, summary, workers_count, issues)
		VALUES ($1, $2, $3, $4, $5, NULLIF($6, ''))
		RETURNING id::text, project_id::text, report_date::text, summary, workers_count,
		          COALESCE(issues, ''), created_at::text
	`, req.ProjectID, userID, req.ReportDate, req.Summary, req.WorkersCount, req.Issues).Scan(&item.ID, &item.ProjectID, &item.ReportDate, &item.Summary, &item.WorkersCount, &item.Issues, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create daily report")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'create', 'daily_report', $3)
	`, userID, req.ProjectID, item.ID)

	JSON(w, http.StatusCreated, item)
}

func updateDailyReport(w http.ResponseWriter, r *http.Request, reportID string) {
	userID := userIDFromContext(r.Context())
	var req createDailyReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	normalizeDailyReportRequest(&req)
	if req.Summary == "" || req.WorkersCount < 0 {
		Error(w, http.StatusBadRequest, "summary and non-negative workers_count are required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := dailyReportProjectID(ctx, reportID)
	if !ok || !canContributeToProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item DailyReportDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		UPDATE daily_reports
		SET report_date = $2, summary = $3, workers_count = $4,
		    issues = NULLIF($5, ''), updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id::text, project_id::text, report_date::text, summary, workers_count,
		          COALESCE(issues, ''), created_at::text
	`, reportID, req.ReportDate, req.Summary, req.WorkersCount, req.Issues).Scan(&item.ID, &item.ProjectID, &item.ReportDate, &item.Summary, &item.WorkersCount, &item.Issues, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "daily report not found")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'update', 'daily_report', $3)
	`, userID, projectID, reportID)

	JSON(w, http.StatusOK, item)
}

func deleteDailyReport(w http.ResponseWriter, r *http.Request, reportID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := dailyReportProjectID(ctx, reportID)
	if !ok || !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	result, err := appState.DB.Pool.Exec(ctx, `
		UPDATE daily_reports
		SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
	`, reportID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete daily report")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "daily report not found")
		return
	}
	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'delete', 'daily_report', $3)
	`, userID, projectID, reportID)
	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func dailyReportProjectID(ctx context.Context, reportID string) (string, bool) {
	var projectID string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text
		FROM daily_reports
		WHERE id = $1 AND deleted_at IS NULL
	`, reportID).Scan(&projectID)
	return projectID, err == nil
}

func normalizeDailyReportRequest(req *createDailyReportRequest) {
	req.ProjectID = strings.TrimSpace(req.ProjectID)
	req.ReportDate = strings.TrimSpace(req.ReportDate)
	req.Summary = strings.TrimSpace(req.Summary)
	req.Issues = strings.TrimSpace(req.Issues)
	if req.ReportDate == "" {
		req.ReportDate = time.Now().UTC().Format("2006-01-02")
	}
}
