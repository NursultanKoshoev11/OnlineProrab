package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func refreshForTest(t *testing.T, token string) (int, sessionResponse) {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session/refresh", strings.NewReader(`{"refresh_token":"`+token+`"}`))
	response := httptest.NewRecorder()
	RefreshSession(response, request)
	var body sessionResponse
	_ = json.Unmarshal(response.Body.Bytes(), &body)
	return response.Code, body
}

func TestRefreshTokenReuseRevokesTheSessionOutsideTheRetryGrace(t *testing.T) {
	db := openMigratedTestDB(t)
	previousState, previousGrace := appState, refreshReuseGrace
	defer func() { appState, refreshReuseGrace = previousState, previousGrace }()
	appState = State{DB: db, JWTSecret: "refresh-reuse-test-signing-key-1234567890", AccessTokenTTL: 15 * time.Minute}
	ctx := context.Background()

	var userID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000601') RETURNING id::text`).Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	original, err := newRefreshToken()
	if err != nil {
		t.Fatalf("new refresh token: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO refresh_sessions (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 day')
	`, userID, hashRefreshToken(original)); err != nil {
		t.Fatalf("seed session: %v", err)
	}

	code, first := refreshForTest(t, original)
	if code != http.StatusOK || first.RefreshToken == "" {
		t.Fatalf("first refresh: %d", code)
	}

	// A retry of a refresh whose response was lost is accepted inside the grace.
	refreshReuseGrace = time.Minute
	code, retried := refreshForTest(t, original)
	if code != http.StatusOK || retried.RefreshToken == "" || retried.RefreshToken == first.RefreshToken {
		t.Fatalf("retry within grace: %d", code)
	}
	if code, _ := refreshForTest(t, first.RefreshToken); code != http.StatusUnauthorized {
		t.Fatalf("token from the lost response must stop working, got %d", code)
	}

	// Outside the grace a replayed token means a stolen copy: revoke the session.
	refreshReuseGrace = 0
	if code, _ := refreshForTest(t, original); code != http.StatusUnauthorized {
		t.Fatalf("replayed token outside grace: %d", code)
	}
	if code, _ := refreshForTest(t, retried.RefreshToken); code != http.StatusUnauthorized {
		t.Fatalf("session must be revoked after reuse, current token still refreshed: %d", code)
	}
}
