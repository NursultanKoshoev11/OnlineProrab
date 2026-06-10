package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

type CostItemDTO struct {
	ID        string  `json:"id"`
	ProjectID string  `json:"project_id"`
	Title     string  `json:"title"`
	Category  string  `json:"category"`
	Amount    float64 `json:"amount"`
	Currency  string  `json:"currency"`
	Vendor    string  `json:"vendor,omitempty"`
	SpentAt   string  `json:"spent_at"`
	CreatedAt string  `json:"created_at,omitempty"`
}

type createCostItemRequest struct {
	ProjectID string  `json:"project_id"`
	Title     string  `json:"title"`
	Category  string  `json:"category"`
	Amount    float64 `json:"amount"`
	Currency  string  `json:"currency"`
	Vendor    string  `json:"vendor"`
	SpentAt   string  `json:"spent_at"`
}

func CostItems(w http.ResponseWriter, r *http.Request) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	switch r.Method {
	case http.MethodGet:
		listCostItems(w, r)
	case http.MethodPost:
		createCostItem(w, r)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func listCostItems(w http.ResponseWriter, r *http.Request) {
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
		SELECT id::text, project_id::text, title, category, amount::float8, currency, COALESCE(vendor, ''), spent_at::text, created_at::text
		FROM cost_items
		WHERE project_id = $1
		ORDER BY spent_at DESC, created_at DESC
	`, projectID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load cost items")
		return
	}
	defer rows.Close()

	items := []CostItemDTO{}
	for rows.Next() {
		var item CostItemDTO
		if err := rows.Scan(&item.ID, &item.ProjectID, &item.Title, &item.Category, &item.Amount, &item.Currency, &item.Vendor, &item.SpentAt, &item.CreatedAt); err != nil {
			Error(w, http.StatusInternalServerError, "failed to scan cost item")
			return
		}
		items = append(items, item)
	}
	JSON(w, http.StatusOK, items)
}

func createCostItem(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createCostItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if req.ProjectID == "" || req.Title == "" || req.Amount < 0 {
		Error(w, http.StatusBadRequest, "project_id, title and non-negative amount are required")
		return
	}
	if req.Category == "" {
		req.Category = "other"
	}
	if req.Currency == "" {
		req.Currency = "KGS"
	}
	if req.SpentAt == "" {
		req.SpentAt = time.Now().UTC().Format("2006-01-02")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canAccessProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item CostItemDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO cost_items (project_id, created_by, title, category, amount, currency, vendor, spent_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8)
		RETURNING id::text, project_id::text, title, category, amount::float8, currency, COALESCE(vendor, ''), spent_at::text, created_at::text
	`, req.ProjectID, userID, req.Title, req.Category, req.Amount, req.Currency, req.Vendor, req.SpentAt).Scan(&item.ID, &item.ProjectID, &item.Title, &item.Category, &item.Amount, &item.Currency, &item.Vendor, &item.SpentAt, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create cost item")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'create', 'cost_item', $3)
	`, userID, req.ProjectID, item.ID)

	JSON(w, http.StatusCreated, item)
}

func canAccessProject(ctx context.Context, userID, projectID string) bool {
	var exists bool
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM project_members
			WHERE user_id = $1 AND project_id = $2
		)
	`, userID, projectID).Scan(&exists)
	return err == nil && exists
}
