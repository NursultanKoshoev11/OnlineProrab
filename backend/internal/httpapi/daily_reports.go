package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
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
		SELECT id::text, project_id::text, report_date::text, summary, workers_count, COALESCE(issues, ''), created_at::text
		FROM daily_reports
		WHERE project_id = $1
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
	JSON(w, http.StatusOK, items)
}

func createDailyReport(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createDailyReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.ProjectID == "" || req.Summary == "" || req.WorkersCount < 0 {
		Error(w, http.StatusBadRequest, "project_id, summary and non-negative workers_count are required")
		return
	}
	if req.ReportDate == "" {
		req.ReportDate = time.Now().UTC().Format("2006-01-02")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item DailyReportDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO daily_reports (project_id, created_by, report_date, summary, workers_count, issues)
		VALUES ($1, $2, $3, $4, $5, NULLIF($6, ''))
		RETURNING id::text, project_id::text, report_date::text, summary, workers_count, COALESCE(issues, ''), created_at::text
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
