package httpapi

import "testing"

func TestNormalizePhoneRemovesSpaces(t *testing.T) {
	got := normalizePhone(" +996 700 000 000 ")
	if got != "+996700000000" {
		t.Fatalf("unexpected normalized phone: %q", got)
	}
}

func TestGenerateSMSCodeReturnsSixDigits(t *testing.T) {
	code, err := generateSMSCode()
	if err != nil {
		t.Fatalf("generateSMSCode returned error: %v", err)
	}
	if len(code) != 6 {
		t.Fatalf("expected 6-digit code, got %q", code)
	}
	for _, ch := range code {
		if ch < '0' || ch > '9' {
			t.Fatalf("expected numeric code, got %q", code)
		}
	}
}

func TestAccessTokenRoundTrip(t *testing.T) {
	oldState := appState
	appState.JWTSecret = "unit-test-secret"
	defer func() { appState = oldState }()

	token, err := signAccessToken("user-1")
	if err != nil {
		t.Fatalf("signAccessToken returned error: %v", err)
	}
	userID, err := parseAccessToken(token)
	if err != nil {
		t.Fatalf("parseAccessToken returned error: %v", err)
	}
	if userID != "user-1" {
		t.Fatalf("expected user-1, got %q", userID)
	}
}
