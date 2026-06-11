package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
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

	costItemID := resourceIDFromPath(r.URL.Path, "/api/v1/cost-items/")
	if costItemID != "" {
		switch r.Method {
		case http.MethodGet:
			getCostItem(w, r, costItemID)
		case http.MethodPatch:
			updateCostItem(w, r, costItemID)
		case http.MethodDelete:
			deleteCostItem(w, r, costItemID)
		default:
			Error(w, http.StatusMethodNotAllowed, "method not allowed")
		}
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
		SELECT id::text, project_id::text, title, category, amount::float8, currency,
		       COALESCE(vendor, ''), spent_at::text, created_at::text
		FROM cost_items
		WHERE project_id = $1 AND deleted_at IS NULL
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
	if err := rows.Err(); err != nil {
		Error(w, http.StatusInternalServerError, "failed to read cost items")
		return
	}
	JSON(w, http.StatusOK, items)
}

func getCostItem(w http.ResponseWriter, r *http.Request, costItemID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := costItemProjectID(ctx, costItemID)
	if !ok || !canAccessProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}

	var item CostItemDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT id::text, project_id::text, title, category, amount::float8, currency,
		       COALESCE(vendor, ''), spent_at::text, created_at::text
		FROM cost_items
		WHERE id = $1 AND deleted_at IS NULL
	`, costItemID).Scan(&item.ID, &item.ProjectID, &item.Title, &item.Category, &item.Amount, &item.Currency, &item.Vendor, &item.SpentAt, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "cost item not found")
		return
	}
	JSON(w, http.StatusOK, item)
}

func createCostItem(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	var req createCostItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	normalizeCostItemRequest(&req)
	if req.ProjectID == "" || req.Title == "" || req.Amount < 0 {
		Error(w, http.StatusBadRequest, "project_id, title and non-negative amount are required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if !canContributeToProject(ctx, userID, req.ProjectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item CostItemDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO cost_items (project_id, created_by, title, category, amount, currency, vendor, spent_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8)
		RETURNING id::text, project_id::text, title, category, amount::float8, currency,
		          COALESCE(vendor, ''), spent_at::text, created_at::text
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

func updateCostItem(w http.ResponseWriter, r *http.Request, costItemID string) {
	userID := userIDFromContext(r.Context())
	var req createCostItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	normalizeCostItemRequest(&req)
	if req.Title == "" || req.Amount < 0 {
		Error(w, http.StatusBadRequest, "title and non-negative amount are required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := costItemProjectID(ctx, costItemID)
	if !ok || !canContributeToProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project contribution permission required")
		return
	}

	var item CostItemDTO
	err := appState.DB.Pool.QueryRow(ctx, `
		UPDATE cost_items
		SET title = $2, category = $3, amount = $4, currency = $5,
		    vendor = NULLIF($6, ''), spent_at = $7, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id::text, project_id::text, title, category, amount::float8, currency,
		          COALESCE(vendor, ''), spent_at::text, created_at::text
	`, costItemID, req.Title, req.Category, req.Amount, req.Currency, req.Vendor, req.SpentAt).Scan(&item.ID, &item.ProjectID, &item.Title, &item.Category, &item.Amount, &item.Currency, &item.Vendor, &item.SpentAt, &item.CreatedAt)
	if err != nil {
		Error(w, http.StatusNotFound, "cost item not found")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'update', 'cost_item', $3)
	`, userID, projectID, costItemID)

	JSON(w, http.StatusOK, item)
}

func deleteCostItem(w http.ResponseWriter, r *http.Request, costItemID string) {
	userID := userIDFromContext(r.Context())
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	projectID, ok := costItemProjectID(ctx, costItemID)
	if !ok || !canManageProject(ctx, userID, projectID) {
		Error(w, http.StatusForbidden, "project management permission required")
		return
	}

	result, err := appState.DB.Pool.Exec(ctx, `
		UPDATE cost_items
		SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
	`, costItemID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to delete cost item")
		return
	}
	if result.RowsAffected() == 0 {
		Error(w, http.StatusNotFound, "cost item not found")
		return
	}
	_, _ = appState.DB.Pool.Exec(ctx, `
		INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id)
		VALUES ($1, $2, 'delete', 'cost_item', $3)
	`, userID, projectID, costItemID)
	JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func canAccessProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionRead)
}

func costItemProjectID(ctx context.Context, costItemID string) (string, bool) {
	var projectID string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT project_id::text
		FROM cost_items
		WHERE id = $1 AND deleted_at IS NULL
	`, costItemID).Scan(&projectID)
	return projectID, err == nil
}

func normalizeCostItemRequest(req *createCostItemRequest) {
	req.ProjectID = strings.TrimSpace(req.ProjectID)
	req.Title = strings.TrimSpace(req.Title)
	req.Category = strings.TrimSpace(req.Category)
	req.Currency = strings.ToUpper(strings.TrimSpace(req.Currency))
	req.Vendor = strings.TrimSpace(req.Vendor)
	req.SpentAt = strings.TrimSpace(req.SpentAt)
	if req.Category == "" {
		req.Category = "other"
	}
	if req.Currency == "" {
		req.Currency = "KGS"
	}
	if req.SpentAt == "" {
		req.SpentAt = time.Now().UTC().Format("2006-01-02")
	}
}
