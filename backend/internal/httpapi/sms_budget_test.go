package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strings"
	"testing"
	"time"
)

type recordingSMSSender struct {
	phones []string
	err    error
}

func (s *recordingSMSSender) SendLoginCode(_ context.Context, phone, _ string) error {
	s.phones = append(s.phones, phone)
	return s.err
}

func smsBudgetTestState(t *testing.T, sender *recordingSMSSender, dailyLimit int) {
	t.Helper()
	db := openSMSAuthTestDB(t)
	oldState := appState
	t.Cleanup(func() { appState = oldState })
	appState = State{
		DB:               db,
		JWTSecret:        "sms-budget-test-signing-key-1234567890",
		AccessTokenTTL:   time.Hour,
		IsProductionLike: true,
		SMSSender:        sender,
		SMSDailyLimit:    dailyLimit,
	}
}

func requestCode(phone string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/request", strings.NewReader(`{"phone":"`+phone+`"}`))
	rec := httptest.NewRecorder()
	RequestSMSCode(rec, req)
	return rec
}

func TestRequestSMSCodeOnlySendsToKyrgyzNumbers(t *testing.T) {
	sender := &recordingSMSSender{}
	smsBudgetTestState(t, sender, 10)

	if rec := requestCode("+447700900123"); rec.Code != http.StatusBadRequest {
		t.Fatalf("foreign number: expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(sender.phones) != 0 {
		t.Fatalf("no SMS may be sent to a foreign number, sent to %v", sender.phones)
	}
	if rec := requestCode("+996700000777"); rec.Code != http.StatusAccepted {
		t.Fatalf("Kyrgyz number: expected 202, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(sender.phones) != 1 {
		t.Fatalf("expected one SMS to the Kyrgyz number, got %v", sender.phones)
	}
}

func TestRequestSMSCodeStopsAtTheDailyBudget(t *testing.T) {
	sender := &recordingSMSSender{}
	smsBudgetTestState(t, sender, 2)
	if _, err := appState.DB.Pool.Exec(context.Background(), `
		INSERT INTO auth_attempts (phone, remote_key, action, succeeded, created_at)
		VALUES ('996700000001', '198.51.100.1', 'sms_request', TRUE, now() - interval '1 hour'),
		       ('996700000002', '198.51.100.2', 'sms_request', TRUE, now() - interval '2 hours'),
		       ('996700000003', '198.51.100.3', 'sms_request', TRUE, now() - interval '25 hours')
	`); err != nil {
		t.Fatalf("seed delivered codes: %v", err)
	}

	if rec := requestCode("+996700000778"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 once the daily budget is spent, got %d: %s", rec.Code, rec.Body.String())
	}
	if len(sender.phones) != 0 {
		t.Fatalf("no SMS may be sent past the daily budget, sent to %v", sender.phones)
	}
}

func TestRequestSMSCodeReportsProviderFailure(t *testing.T) {
	sender := &recordingSMSSender{err: errors.New("Nikita rejected SMS with status 4")}
	smsBudgetTestState(t, sender, 10)

	if rec := requestCode("+996700000779"); rec.Code != http.StatusBadGateway {
		t.Fatalf("expected 502 when the provider fails, got %d: %s", rec.Code, rec.Body.String())
	}
	var stored int
	if err := appState.DB.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM sms_login_codes`).Scan(&stored); err != nil {
		t.Fatalf("count codes: %v", err)
	}
	if stored != 0 {
		t.Fatalf("an undelivered code must not stay usable, found %d", stored)
	}
}

func TestRemoteClientKeyGroupsIPv6By64(t *testing.T) {
	a := remoteClientKey(netip.MustParseAddr("2001:db8:1:2:aaaa::1"))
	b := remoteClientKey(netip.MustParseAddr("2001:db8:1:2:bbbb::9"))
	c := remoteClientKey(netip.MustParseAddr("2001:db8:1:3::1"))
	if a != b || a != "2001:db8:1:2::/64" {
		t.Fatalf("addresses in one /64 must share a key, got %q and %q", a, b)
	}
	if a == c {
		t.Fatalf("different /64 networks must not share a key")
	}
	if got := remoteClientKey(netip.MustParseAddr("::ffff:198.51.100.7")); got != "198.51.100.7" {
		t.Fatalf("IPv4 clients keep their own address, got %q", got)
	}
}
