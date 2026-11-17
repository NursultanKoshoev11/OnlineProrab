package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

const (
	refreshTokenTTL             = 60 * 24 * time.Hour
	maxActiveUserSessions       = 10
	refreshSessionRetentionDays = 30
)

type createSessionRequest struct {
	DeviceName string `json:"device_name"`
}

type refreshSessionRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type sessionResponse struct {
	AccessToken  string `json:"access_token,omitempty"`
	RefreshToken string `json:"refresh_token,omitempty"`
	TokenType    string `json:"token_type,omitempty"`
	ExpiresIn    int64  `json:"expires_in,omitempty"`
}

func CreateSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	bootstrapID := sessionBootstrapIDFromContext(r.Context())
	if bootstrapID == "" {
		Error(w, http.StatusUnauthorized, "valid login session token is required")
		return
	}

	var req createSessionRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	req.DeviceName = strings.TrimSpace(req.DeviceName)
	if len(req.DeviceName) > 200 {
		Error(w, http.StatusBadRequest, "device_name is too long")
		return
	}

	userID := userIDFromContext(r.Context())
	refreshToken, err := newRefreshToken()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create session")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start session creation")
		return
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, "stroy:sessions:user:"+userID); err != nil {
		Error(w, http.StatusServiceUnavailable, "session service is temporarily unavailable")
		return
	}

	var consumedUserID string
	err = tx.QueryRow(ctx, `
		DELETE FROM auth_session_bootstrap_tokens
		WHERE token_hash = $1 AND user_id = $2 AND expires_at > now()
		RETURNING user_id::text
	`, hashSessionBootstrapID(bootstrapID), userID).Scan(&consumedUserID)
	if err != nil || consumedUserID != userID {
		Error(w, http.StatusUnauthorized, "login session token is expired or already used")
		return
	}

	_, _ = tx.Exec(ctx, `
		DELETE FROM refresh_sessions
		WHERE expires_at < now() - make_interval(days => $1)
		   OR (revoked_at IS NOT NULL AND revoked_at < now() - make_interval(days => $1))
	`, refreshSessionRetentionDays)

	_, err = tx.Exec(ctx, `
		WITH sessions_to_revoke AS (
			SELECT id
			FROM refresh_sessions
			WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()
			ORDER BY COALESCE(last_used_at, created_at) DESC
			OFFSET $2
		)
		UPDATE refresh_sessions
		SET revoked_at = now()
		WHERE id IN (SELECT id FROM sessions_to_revoke)
	`, userID, maxActiveUserSessions-1)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to enforce session limit")
		return
	}

	var sessionID string
	err = tx.QueryRow(ctx, `
		INSERT INTO refresh_sessions (user_id, token_hash, device_name, expires_at)
		VALUES ($1, $2, NULLIF($3, ''), $4)
		RETURNING id::text
	`, userID, hashRefreshToken(refreshToken), req.DeviceName, time.Now().UTC().Add(refreshTokenTTL)).Scan(&sessionID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save session")
		return
	}
	accessToken, err := signSessionAccessToken(userID, sessionID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to sign access token")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit session")
		return
	}

	JSON(w, http.StatusCreated, sessionResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		TokenType:    "Bearer",
		ExpiresIn:    int64(appState.AccessTokenTTL.Seconds()),
	})
}

func RefreshSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	var req refreshSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.RefreshToken = strings.TrimSpace(req.RefreshToken)
	if req.RefreshToken == "" {
		Error(w, http.StatusBadRequest, "refresh_token is required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start session refresh")
		return
	}
	defer tx.Rollback(ctx)

	var sessionID string
	var userID string
	err = tx.QueryRow(ctx, `
		SELECT id::text, user_id::text
		FROM refresh_sessions
		WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
		FOR UPDATE
	`, hashRefreshToken(req.RefreshToken)).Scan(&sessionID, &userID)
	if err != nil {
		Error(w, http.StatusUnauthorized, "invalid or expired refresh token")
		return
	}

	newToken, err := newRefreshToken()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to rotate session")
		return
	}
	_, err = tx.Exec(ctx, `
		UPDATE refresh_sessions
		SET token_hash = $2, expires_at = $3, last_used_at = now()
		WHERE id = $1
	`, sessionID, hashRefreshToken(newToken), time.Now().UTC().Add(refreshTokenTTL))
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to rotate session")
		return
	}

	accessToken, err := signSessionAccessToken(userID, sessionID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to sign access token")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit session refresh")
		return
	}

	JSON(w, http.StatusOK, sessionResponse{
		AccessToken:  accessToken,
		RefreshToken: newToken,
		TokenType:    "Bearer",
		ExpiresIn:    int64(appState.AccessTokenTTL.Seconds()),
	})
}

func LogoutSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	var req refreshSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.RefreshToken = strings.TrimSpace(req.RefreshToken)
	if req.RefreshToken == "" {
		Error(w, http.StatusBadRequest, "refresh_token is required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	var err error
	identity, tokenErr := parseAuthenticatedToken(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") && tokenErr == nil && identity.SessionID != "" {
		_, err = appState.DB.Pool.Exec(ctx, `
			UPDATE refresh_sessions
			SET revoked_at = COALESCE(revoked_at, now())
			WHERE id = $1 AND user_id = $2
		`, identity.SessionID, identity.UserID)
	} else {
		_, err = appState.DB.Pool.Exec(ctx, `
			UPDATE refresh_sessions
			SET revoked_at = COALESCE(revoked_at, now())
			WHERE token_hash = $1
		`, hashRefreshToken(req.RefreshToken))
	}
	if err != nil {
		Error(w, http.StatusServiceUnavailable, "session service is temporarily unavailable")
		return
	}
	JSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func newSessionBootstrapID() (string, error) {
	buffer := make([]byte, 32)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

func hashSessionBootstrapID(id string) string {
	sum := sha256.Sum256([]byte(id))
	return hex.EncodeToString(sum[:])
}

func newRefreshToken() (string, error) {
	buffer := make([]byte, 32)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buffer), nil
}

func hashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
