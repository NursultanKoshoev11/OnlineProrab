package httpapi

import (
	"context"
	"net/http"
	"time"
)

// requireSubscribed protects application data and mutations while keeping the
// subscription status and checkout endpoints available for renewal.
func requireSubscribed(next http.HandlerFunc) http.HandlerFunc {
	return requireAuth(func(w http.ResponseWriter, r *http.Request) {
		userID := userIDFromContext(r.Context())
		if userID == "" || !requireCurrentSubscription(w, r, userID) {
			return
		}
		next(w, r)
	})
}

func requireCurrentSubscription(w http.ResponseWriter, r *http.Request, userID string) bool {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "subscription service is unavailable")
		return false
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	state, err := ensureSubscription(ctx, appState.DB.Pool, userID, false)
	if err != nil {
		Error(w, http.StatusServiceUnavailable, "subscription service is unavailable")
		return false
	}
	if state.Status != "trialing" && state.Status != "active" {
		// An invited member without a plan of their own may still work in
		// projects whose owner pays; per-project checks enforce the owner's
		// subscription (see ownerSubscriptionCurrentSQL).
		if memberOfPaidProject(ctx, userID) {
			return true
		}
		status, message, _ := subscriptionHTTPError(errSubscriptionExpired)
		Error(w, status, message)
		return false
	}
	return true
}

func memberOfPaidProject(ctx context.Context, userID string) bool {
	var ok bool
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM project_members pm
			JOIN projects p ON p.id = pm.project_id
			WHERE pm.user_id = $1
			  AND p.owner_id <> $1
			  AND p.deleted_at IS NULL
			  AND `+ownerSubscriptionCurrentSQL+`
		)
	`, userID).Scan(&ok)
	return err == nil && ok
}
