package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// Unknown numbers may use only part of the daily SMS budget, so a flood of
// fake sign-ups leaves room for existing customers to log in.
func TestSMSBudgetKeepsAShareForExistingAccounts(t *testing.T) {
	sender := &recordingSMSSender{}
	smsBudgetTestState(t, sender, 10)
	ctx := context.Background()
	if _, err := appState.DB.Pool.Exec(ctx, `INSERT INTO users (phone) VALUES ('+996700000880')`); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	if _, err := appState.DB.Pool.Exec(ctx, `
		INSERT INTO auth_attempts (phone, remote_key, action, succeeded, created_at)
		SELECT '9967000009' || g, '198.51.100.' || g, 'sms_request', TRUE, now() - interval '1 hour'
		FROM generate_series(10, 16) AS g
	`); err != nil {
		t.Fatalf("seed delivered codes: %v", err)
	}

	if rec := requestCode("+996700000881"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("new number past its share: expected 503, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec := requestCode("+996700000880"); rec.Code != http.StatusAccepted {
		t.Fatalf("existing account within the reserve: expected 202, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(sender.phones) != 1 || sender.phones[0] != "+996700000880" {
		t.Fatalf("expected one SMS to the existing account, got %v", sender.phones)
	}
}

// Wrong codes sent by someone else must not lock the phone's owner out.
func TestSMSVerifyLimitIsPerClient(t *testing.T) {
	smsBudgetTestState(t, &recordingSMSSender{}, 10)
	handler := withSMSVerifyRateLimit(func(w http.ResponseWriter, r *http.Request) {
		Error(w, http.StatusBadRequest, "invalid code")
	})
	verify := func(remote string) int {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/verify", strings.NewReader(`{"phone":"+996700000890","code":"000000"}`))
		req.RemoteAddr = remote + ":40000"
		rec := httptest.NewRecorder()
		handler(rec, req)
		return rec.Code
	}

	for i := 0; i < maxVerifyAttemptsPhone; i++ {
		if code := verify("203.0.113.7"); code != http.StatusBadRequest {
			t.Fatalf("attempt %d from attacker: expected 400, got %d", i+1, code)
		}
	}
	if code := verify("203.0.113.7"); code != http.StatusTooManyRequests {
		t.Fatalf("attacker past the limit: expected 429, got %d", code)
	}
	if code := verify("198.51.100.20"); code != http.StatusBadRequest {
		t.Fatalf("owner on another network must still reach verification, got %d", code)
	}
}

// One account may send only a few support messages per hour.
func TestUserRateLimitCapsSupportTickets(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	t.Cleanup(func() { appState = oldState })
	appState = State{DB: db}
	handler := withUserRateLimit("support_ticket", supportTicketWindow, supportTicketLimit, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	})
	post := func(userID string) int {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/support/tickets", strings.NewReader(`{}`))
		req = req.WithContext(withUserID(req.Context(), userID))
		rec := httptest.NewRecorder()
		handler(rec, req)
		return rec.Code
	}
	const spammer = "11111111-1111-4111-8111-111111111111"
	const other = "22222222-2222-4222-8222-222222222222"
	for i := 0; i < supportTicketLimit; i++ {
		if code := post(spammer); code != http.StatusCreated {
			t.Fatalf("ticket %d: expected 201, got %d", i+1, code)
		}
	}
	if code := post(spammer); code != http.StatusTooManyRequests {
		t.Fatalf("ticket past the limit: expected 429, got %d", code)
	}
	if code := post(other); code != http.StatusCreated {
		t.Fatalf("another account must not be limited, got %d", code)
	}
}

// An open realtime stream stops once its session is revoked.
func TestRealtimeAccessEndsWithRevokedSession(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	t.Cleanup(func() { appState = oldState })
	appState = State{DB: db}
	ctx := context.Background()

	var userID, sessionID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000895') RETURNING id::text`).Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	if err := db.Pool.QueryRow(ctx, `
		INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
		VALUES ($1, 'realtime-test-session', $2) RETURNING id::text
	`, userID, time.Now().Add(time.Hour)).Scan(&sessionID); err != nil {
		t.Fatalf("seed session: %v", err)
	}

	if !realtimeAccessStillValid(ctx, userID, sessionID, "") {
		t.Fatal("an active session must keep its stream")
	}
	if _, err := db.Pool.Exec(ctx, `UPDATE refresh_sessions SET revoked_at = now() WHERE id = $1`, sessionID); err != nil {
		t.Fatalf("revoke session: %v", err)
	}
	if realtimeAccessStillValid(ctx, userID, sessionID, "") {
		t.Fatal("a revoked session must close its stream")
	}
}
