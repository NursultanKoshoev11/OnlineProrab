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
		status, message, _ := subscriptionHTTPError(errSubscriptionExpired)
		Error(w, status, message)
		return false
	}
	return true
}
