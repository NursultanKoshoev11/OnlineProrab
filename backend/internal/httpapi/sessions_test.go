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

func TestSessionBootstrapTokenCanCreateOnlyOneBoundSession(t *testing.T) {
	db := openSMSAuthTestDB(t)
	previousState := appState
	defer func() { appState = previousState }()
	appState = State{DB: db, JWTSecret: "session-test-signing-key-1234567890", AccessTokenTTL: 15 * time.Minute}

	userID := insertExpenseAIRateLimitTestUser(t, context.Background())
	bootstrapID, err := newSessionBootstrapID()
	if err != nil {
		t.Fatalf("create bootstrap id: %v", err)
	}
	bootstrapToken, err := signSessionBootstrapToken(userID, bootstrapID)
	if err != nil {
		t.Fatalf("sign bootstrap token: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO auth_session_bootstrap_tokens (token_hash, user_id, expires_at)
		VALUES ($1, $2, now() + interval '2 minutes')
	`, hashSessionBootstrapID(bootstrapID), userID); err != nil {
		t.Fatalf("persist bootstrap token: %v", err)
	}

	protected := requireAuth(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	protectedRequest := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
	protectedRequest.Header.Set("Authorization", "Bearer "+bootstrapToken)
	protectedResponse := httptest.NewRecorder()
	protected.ServeHTTP(protectedResponse, protectedRequest)
	if protectedResponse.Code != http.StatusUnauthorized {
		t.Fatalf("bootstrap token reached a protected resource: %d", protectedResponse.Code)
	}

	create := requireAuth(CreateSession)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session", strings.NewReader(`{"device_name":"test"}`))
	request.Header.Set("Authorization", "Bearer "+bootstrapToken)
	response := httptest.NewRecorder()
	create.ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("create session: status=%d body=%s", response.Code, response.Body.String())
	}
	var session sessionResponse
	if err := json.Unmarshal(response.Body.Bytes(), &session); err != nil {
		t.Fatalf("decode session response: %v", err)
	}
	if session.AccessToken == "" || session.RefreshToken == "" {
		t.Fatalf("session response did not include both tokens: %+v", session)
	}
	identity, err := parseAuthenticatedToken(session.AccessToken)
	if err != nil || identity.UserID != userID || identity.SessionID == "" {
		t.Fatalf("session access token is not bound to the new session: %+v error=%v", identity, err)
	}

	replay := httptest.NewRecorder()
	replayRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session", strings.NewReader(`{"device_name":"test"}`))
	replayRequest.Header.Set("Authorization", "Bearer "+bootstrapToken)
	create.ServeHTTP(replay, replayRequest)
	if replay.Code != http.StatusUnauthorized {
		t.Fatalf("bootstrap token replay returned %d, want unauthorized", replay.Code)
	}
}

func TestLogoutImmediatelyRevokesBoundAccessToken(t *testing.T) {
	db := openSMSAuthTestDB(t)
	previousState := appState
	defer func() { appState = previousState }()
	appState = State{DB: db, JWTSecret: "session-test-signing-key-1234567890", AccessTokenTTL: time.Hour}

	userID := insertExpenseAIRateLimitTestUser(t, context.Background())
	refreshToken, err := newRefreshToken()
	if err != nil {
		t.Fatalf("create refresh token: %v", err)
	}
	var sessionID string
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
		VALUES ($1, $2, now() + interval '1 day')
		RETURNING id::text
	`, userID, hashRefreshToken(refreshToken)).Scan(&sessionID); err != nil {
		t.Fatalf("create refresh session: %v", err)
	}
	accessToken, err := signSessionAccessToken(userID, sessionID)
	if err != nil {
		t.Fatalf("sign session access token: %v", err)
	}
	protected := requireAuth(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	accessRequest := func() *httptest.ResponseRecorder {
		request := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
		request.Header.Set("Authorization", "Bearer "+accessToken)
		response := httptest.NewRecorder()
		protected.ServeHTTP(response, request)
		return response
	}
	if response := accessRequest(); response.Code != http.StatusNoContent {
		t.Fatalf("active session access returned %d: %s", response.Code, response.Body.String())
	}
	rotatedToken, err := newRefreshToken()
	if err != nil {
		t.Fatalf("create rotated refresh token: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		UPDATE refresh_sessions SET token_hash = $2 WHERE id = $1
	`, sessionID, hashRefreshToken(rotatedToken)); err != nil {
		t.Fatalf("simulate concurrent refresh: %v", err)
	}

	logoutRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session/logout", strings.NewReader(`{"refresh_token":"`+refreshToken+`"}`))
	logoutRequest.Header.Set("Authorization", "Bearer "+accessToken)
	logoutResponse := httptest.NewRecorder()
	LogoutSession(logoutResponse, logoutRequest)
	if logoutResponse.Code != http.StatusOK {
		t.Fatalf("logout failed: %d %s", logoutResponse.Code, logoutResponse.Body.String())
	}
	if response := accessRequest(); response.Code != http.StatusUnauthorized {
		t.Fatalf("revoked session access returned %d, want unauthorized", response.Code)
	}
	refreshRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session/refresh", strings.NewReader(`{"refresh_token":"`+rotatedToken+`"}`))
	refreshResponse := httptest.NewRecorder()
	RefreshSession(refreshResponse, refreshRequest)
	if refreshResponse.Code != http.StatusUnauthorized {
		t.Fatalf("rotated refresh token survived logout: %d", refreshResponse.Code)
	}
}

func TestLogoutFallsBackToRefreshTokenWhenAccessTokenExpired(t *testing.T) {
	db := openSMSAuthTestDB(t)
	previousState := appState
	defer func() { appState = previousState }()
	appState = State{DB: db, JWTSecret: "session-test-signing-key-1234567890", AccessTokenTTL: -time.Minute}

	userID := insertExpenseAIRateLimitTestUser(t, context.Background())
	refreshToken, err := newRefreshToken()
	if err != nil {
		t.Fatalf("create refresh token: %v", err)
	}
	var sessionID string
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
		VALUES ($1, $2, now() + interval '1 day')
		RETURNING id::text
	`, userID, hashRefreshToken(refreshToken)).Scan(&sessionID); err != nil {
		t.Fatalf("create refresh session: %v", err)
	}
	expiredAccessToken, err := signSessionAccessToken(userID, sessionID)
	if err != nil {
		t.Fatalf("sign expired access token: %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session/logout", strings.NewReader(`{"refresh_token":"`+refreshToken+`"}`))
	request.Header.Set("Authorization", "Bearer "+expiredAccessToken)
	response := httptest.NewRecorder()
	LogoutSession(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("logout with expired access token failed: %d %s", response.Code, response.Body.String())
	}

	refreshRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/session/refresh", strings.NewReader(`{"refresh_token":"`+refreshToken+`"}`))
	refreshResponse := httptest.NewRecorder()
	RefreshSession(refreshResponse, refreshRequest)
	if refreshResponse.Code != http.StatusUnauthorized {
		t.Fatalf("refresh token survived logout with expired access token: %d", refreshResponse.Code)
	}
}

func TestNewRefreshTokenIsRandomAndLongEnough(t *testing.T) {
	first, err := newRefreshToken()
	if err != nil {
		t.Fatalf("newRefreshToken returned error: %v", err)
	}
	second, err := newRefreshToken()
	if err != nil {
		t.Fatalf("newRefreshToken returned error: %v", err)
	}
	if first == second {
		t.Fatal("expected unique refresh tokens")
	}
	if len(first) < 40 || len(second) < 40 {
		t.Fatalf("expected long refresh tokens, got lengths %d and %d", len(first), len(second))
	}
}

func TestHashRefreshTokenIsDeterministicAndDoesNotExposeToken(t *testing.T) {
	token := "refresh-token-value"
	first := hashRefreshToken(token)
	second := hashRefreshToken(token)
	if first != second {
		t.Fatal("expected deterministic refresh token hash")
	}
	if first == token {
		t.Fatal("refresh token hash must not equal the raw token")
	}
	if len(first) != 64 {
		t.Fatalf("expected SHA-256 hex hash length 64, got %d", len(first))
	}
}

func TestHashRefreshTokenChangesWithInput(t *testing.T) {
	if hashRefreshToken("token-a") == hashRefreshToken("token-b") {
		t.Fatal("different refresh tokens must have different hashes")
	}
}
