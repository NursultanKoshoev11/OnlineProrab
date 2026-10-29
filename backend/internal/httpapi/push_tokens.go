package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

type pushTokenRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

// PushTokens registers the current device token. A token belongs to one user
// at a time, so logging in on another account safely reassigns it.
func PushTokens(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r.Context())
	if userID == "" || appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	switch r.Method {
	case http.MethodPost:
		var req pushTokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			Error(w, http.StatusBadRequest, "invalid JSON body")
			return
		}
		req.Token = strings.TrimSpace(req.Token)
		req.Platform = strings.ToLower(strings.TrimSpace(req.Platform))
		if req.Token == "" || len(req.Token) > 4096 || (req.Platform != "android" && req.Platform != "ios") {
			Error(w, http.StatusBadRequest, "token and platform (android or ios) are required")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		_, err := appState.DB.Pool.Exec(ctx, `
			INSERT INTO push_tokens (user_id, token, platform, last_seen_at)
			VALUES ($1, $2, $3, now())
			ON CONFLICT (token) DO UPDATE
			SET user_id = EXCLUDED.user_id,
			    platform = EXCLUDED.platform,
			    updated_at = now(),
			    last_seen_at = now()
		`, userID, req.Token, req.Platform)
		if err != nil {
			Error(w, http.StatusInternalServerError, "failed to register push token")
			return
		}
		JSON(w, http.StatusNoContent, nil)
	case http.MethodDelete:
		var req pushTokenRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			Error(w, http.StatusBadRequest, "invalid JSON body")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		_, err := appState.DB.Pool.Exec(ctx, `DELETE FROM push_tokens WHERE user_id = $1 AND token = $2`, userID, strings.TrimSpace(req.Token))
		if err != nil {
			Error(w, http.StatusInternalServerError, "failed to remove push token")
			return
		}
		JSON(w, http.StatusNoContent, nil)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}
