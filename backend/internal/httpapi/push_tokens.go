package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type pushTokenRequest struct {
	Token          string `json:"token"`
	InstallationID string `json:"installation_id"`
	TargetType     string `json:"target_type"`
	Platform       string `json:"platform"`
}

func (req pushTokenRequest) resolveTarget() (string, string, error) {
	token := strings.TrimSpace(req.Token)
	installationID := strings.TrimSpace(req.InstallationID)
	targetType := strings.ToLower(strings.TrimSpace(req.TargetType))
	if targetType == "" {
		switch {
		case installationID != "":
			targetType = "fid"
		case looksLikeFirebaseInstallationID(token):
			// Older app builds posted the firebase_messaging 17 FID in the
			// legacy token field. Infer its type to preserve those installations.
			targetType = "fid"
		default:
			targetType = "token"
		}
	}

	var identifier string
	switch targetType {
	case "fid":
		if token != "" && installationID != "" {
			return "", "", fmt.Errorf("provide only one Firebase installation ID")
		}
		identifier = installationID
		if identifier == "" {
			identifier = token
		}
	case "token":
		if installationID != "" {
			return "", "", fmt.Errorf("installation_id requires target_type fid")
		}
		identifier = token
	default:
		return "", "", fmt.Errorf("target_type must be fid or token")
	}
	if identifier == "" || len(identifier) > 4096 {
		return "", "", fmt.Errorf("a non-empty Firebase target of at most 4096 bytes is required")
	}
	return identifier, targetType, nil
}

func looksLikeFirebaseInstallationID(value string) bool {
	if len(value) != 22 {
		return false
	}
	for _, char := range value {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || char == '_' || char == '-' {
			continue
		}
		return false
	}
	return true
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
		identifier, targetType, err := req.resolveTarget()
		if err != nil {
			Error(w, http.StatusBadRequest, err.Error())
			return
		}
		req.Platform = strings.ToLower(strings.TrimSpace(req.Platform))
		if req.Platform != "android" && req.Platform != "ios" {
			Error(w, http.StatusBadRequest, "platform (android or ios) is required")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		_, err = appState.DB.Pool.Exec(ctx, `
			INSERT INTO push_tokens (user_id, token, target_type, platform, last_seen_at)
			VALUES ($1, $2, $3, $4, now())
			ON CONFLICT (token) DO UPDATE
			SET user_id = EXCLUDED.user_id,
			    target_type = EXCLUDED.target_type,
			    platform = EXCLUDED.platform,
			    updated_at = now(),
			    last_seen_at = now()
		`, userID, identifier, targetType, req.Platform)
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
		identifier, targetType, err := req.resolveTarget()
		if err != nil {
			Error(w, http.StatusBadRequest, err.Error())
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		_, err = appState.DB.Pool.Exec(ctx, `DELETE FROM push_tokens WHERE user_id = $1 AND token = $2 AND target_type = $3`, userID, identifier, targetType)
		if err != nil {
			Error(w, http.StatusInternalServerError, "failed to remove push token")
			return
		}
		JSON(w, http.StatusNoContent, nil)
	default:
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}
