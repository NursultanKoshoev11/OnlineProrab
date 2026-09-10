package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

func ListPlans(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"plans": []map[string]any{
			{"id": "free", "name": "Free", "price_kgs": 0, "max_projects": 1},
			{"id": "pro", "name": "Pro", "price_kgs": 990, "max_projects": 5},
			{"id": "business", "name": "Business", "price_kgs": 2990, "max_projects": 25},
		},
	})
}

func SubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	userID := userIDFromContext(r.Context())
	var plan, status string
	var periodEnd *time.Time
	err := appState.DB.Pool.QueryRow(r.Context(), `
		SELECT plan_code, status, current_period_end
		FROM subscriptions
		WHERE user_id = $1
		  AND status IN ('active', 'trialing')
		  AND (current_period_end IS NULL OR current_period_end > now())
		ORDER BY current_period_end DESC NULLS LAST, updated_at DESC
		LIMIT 1
	`, userID).Scan(&plan, &status, &periodEnd)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		Error(w, http.StatusInternalServerError, "failed to read subscription status")
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		// A user without a paid subscription is a valid free account.
		plan = "free"
		status = "active"
		periodEnd = nil
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id":           userID,
		"plan":              strings.TrimSpace(plan),
		"status":            strings.TrimSpace(status),
		"current_period_end": periodEnd,
	})
}
