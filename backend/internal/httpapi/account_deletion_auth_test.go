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

func TestVerifyAccountDeletionSMSCodeDoesNotMutateAccountOrAcceptInvites(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{
		DB:        db,
		JWTSecret: "account-deletion-test-signing-key-1234567890",
	}

	const phone = "+996700000201"
	const code = "001234"
	var userID string
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO users (phone, updated_at)
		VALUES ($1, now() - interval '1 day')
		RETURNING id::text
	`, phone).Scan(&userID); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO project_invites (project_id, phone, role, expires_at)
		VALUES ('00000000-0000-0000-0000-000000000001', $1, 'viewer', now() + interval '1 day')
	`, phone); err != nil {
		t.Fatalf("seed pending project invitation: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, now() + interval '5 minutes')
	`, phone, hashLoginCode(phone, code)); err != nil {
		t.Fatalf("seed SMS code: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/account/deletion/verify", strings.NewReader(`{"phone":"+996700000201","code":"001234"}`))
	rec := httptest.NewRecorder()
	VerifyAccountDeletionSMSCode(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected deletion verification to succeed, got %d: %s", rec.Code, rec.Body.String())
	}
	var response authResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode deletion verification response: %v", err)
	}
	if response.UserID != userID || response.ExpiresIn != int64(accountDeletionTokenTTL.Seconds()) {
		t.Fatalf("unexpected deletion verification response: %+v", response)
	}
	if got, err := parseAccountDeletionToken(response.AccessToken); err != nil || got != userID {
		t.Fatalf("expected scoped token for user %s, got user %q and error %v", userID, got, err)
	}
	if _, err := parseAccessToken(response.AccessToken); err == nil {
		t.Fatal("deletion token must not authorize ordinary API routes")
	}

	var updatedAt time.Time
	if err := db.Pool.QueryRow(context.Background(), `SELECT updated_at FROM users WHERE id = $1`, userID).Scan(&updatedAt); err != nil {
		t.Fatalf("read account after verification: %v", err)
	}
	if time.Since(updatedAt) < 23*time.Hour {
		t.Fatalf("deletion verification unexpectedly modified the account timestamp: %s", updatedAt)
	}
	var acceptedInvites int
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM project_invites WHERE phone = $1 AND accepted_at IS NOT NULL`, phone).Scan(&acceptedInvites); err != nil {
		t.Fatalf("read pending invitations after verification: %v", err)
	}
	if acceptedInvites != 0 {
		t.Fatalf("deletion verification accepted %d project invitations", acceptedInvites)
	}
	var consumedCodes int
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM sms_login_codes WHERE phone = $1 AND consumed_at IS NOT NULL`, phone).Scan(&consumedCodes); err != nil {
		t.Fatalf("read SMS code after verification: %v", err)
	}
	if consumedCodes != 1 {
		t.Fatalf("expected the deletion SMS code to be consumed, got %d consumed codes", consumedCodes)
	}
}

func TestScopedDeletionTokenIsAcceptedOnlyByAccountDeletionAuth(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	appState = State{DB: db, JWTSecret: "account-deletion-test-signing-key-1234567890"}
	defer func() { appState = oldState }()
	var deletionUserID, appUserID string
	if err := db.Pool.QueryRow(context.Background(), `INSERT INTO users (phone) VALUES ('+996700000203') RETURNING id::text`).Scan(&deletionUserID); err != nil {
		t.Fatalf("create account for deletion token: %v", err)
	}
	if err := db.Pool.QueryRow(context.Background(), `INSERT INTO users (phone) VALUES ('+996700000204') RETURNING id::text`).Scan(&appUserID); err != nil {
		t.Fatalf("create account for app access token: %v", err)
	}
	token, err := signAccountDeletionToken(deletionUserID)
	if err != nil {
		t.Fatalf("sign deletion token: %v", err)
	}

	ordinaryHandler := requireAuth(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	ordinaryReq := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
	ordinaryReq.Header.Set("Authorization", "Bearer "+token)
	ordinaryRec := httptest.NewRecorder()
	ordinaryHandler(ordinaryRec, ordinaryReq)
	if ordinaryRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected ordinary API to reject deletion token, got %d", ordinaryRec.Code)
	}

	deletionHandler := requireAccountDeletionAuth(func(w http.ResponseWriter, r *http.Request) {
		if got := userIDFromContext(r.Context()); got != deletionUserID {
			t.Errorf("expected deletion-authenticated user %q, got %q", deletionUserID, got)
		}
		w.WriteHeader(http.StatusNoContent)
	})
	deletionReq := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	deletionReq.Header.Set("Authorization", "Bearer "+token)
	deletionRec := httptest.NewRecorder()
	deletionHandler(deletionRec, deletionReq)
	if deletionRec.Code != http.StatusNoContent {
		t.Fatalf("expected account deletion auth to accept scoped token, got %d", deletionRec.Code)
	}

	accessToken, err := signAccessToken(appUserID)
	if err != nil {
		t.Fatalf("sign normal access token: %v", err)
	}
	appDeletionHandler := requireAccountDeletionAuth(func(w http.ResponseWriter, r *http.Request) {
		if got := userIDFromContext(r.Context()); got != appUserID {
			t.Errorf("expected app-authenticated user %q, got %q", appUserID, got)
		}
		w.WriteHeader(http.StatusNoContent)
	})
	appReq := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	appReq.Header.Set("Authorization", "Bearer "+accessToken)
	appRec := httptest.NewRecorder()
	appDeletionHandler(appRec, appReq)
	if appRec.Code != http.StatusNoContent {
		t.Fatalf("expected account deletion auth to preserve normal app tokens, got %d", appRec.Code)
	}
}

func TestVerifyAccountDeletionSMSCodeConsumesCodeWithoutCreatingMissingAccount(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{
		DB:        db,
		JWTSecret: "account-deletion-test-signing-key-1234567890",
	}

	const phone = "+996700000202"
	const code = "001235"
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, now() + interval '5 minutes')
	`, phone, hashLoginCode(phone, code)); err != nil {
		t.Fatalf("seed SMS code: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/account/deletion/verify", strings.NewReader(`{"phone":"+996700000202","code":"001235"}`))
	rec := httptest.NewRecorder()
	VerifyAccountDeletionSMSCode(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected missing account to return 404, got %d: %s", rec.Code, rec.Body.String())
	}
	var accounts int
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM users`).Scan(&accounts); err != nil {
		t.Fatalf("count users after verification: %v", err)
	}
	if accounts != 0 {
		t.Fatalf("deletion verification created %d accounts", accounts)
	}
	var consumedCodes int
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM sms_login_codes WHERE phone = $1 AND consumed_at IS NOT NULL`, phone).Scan(&consumedCodes); err != nil {
		t.Fatalf("read SMS code after verification: %v", err)
	}
	if consumedCodes != 1 {
		t.Fatalf("expected the deletion SMS code to be consumed, got %d consumed codes", consumedCodes)
	}
}
