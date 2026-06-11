package httpapi

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

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
	appState.JWTSecret = "unit-test-signing-key-1234567890"
	appState.AccessTokenTTL = time.Hour
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

func TestAccessTokenRejectsExpiredToken(t *testing.T) {
	oldState := appState
	appState.JWTSecret = "unit-test-signing-key-1234567890"
	defer func() { appState = oldState }()

	claims := jwt.MapClaims{
		"sub": "user-1",
		"exp": time.Now().Add(-time.Minute).Unix(),
		"iat": time.Now().Add(-time.Hour).Unix(),
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(appState.JWTSecret))
	if err != nil {
		t.Fatalf("failed to sign expired token: %v", err)
	}
	if _, err := parseAccessToken(token); err == nil {
		t.Fatal("expected expired token to be rejected")
	}
}

func TestAccessTokenRejectsTokenSignedWithDifferentKey(t *testing.T) {
	oldState := appState
	appState.JWTSecret = "unit-test-signing-key-1234567890"
	defer func() { appState = oldState }()

	claims := jwt.MapClaims{
		"sub": "user-1",
		"exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Unix(),
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte("different-signing-key-1234567890"))
	if err != nil {
		t.Fatalf("failed to sign token: %v", err)
	}
	if _, err := parseAccessToken(token); err == nil {
		t.Fatal("expected token signed with different key to be rejected")
	}
}

func TestAccessTokenRejectsDifferentHMACAlgorithm(t *testing.T) {
	oldState := appState
	appState.JWTSecret = "unit-test-signing-key-1234567890"
	defer func() { appState = oldState }()

	claims := jwt.MapClaims{
		"sub": "user-1",
		"exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Unix(),
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS384, claims).SignedString([]byte(appState.JWTSecret))
	if err != nil {
		t.Fatalf("failed to sign HS384 token: %v", err)
	}
	if _, err := parseAccessToken(token); err == nil {
		t.Fatal("expected HS384 token to be rejected")
	}
}

func TestHashLoginCodeDependsOnPhoneAndCode(t *testing.T) {
	oldState := appState
	appState.JWTSecret = "unit-test-signing-key-1234567890"
	defer func() { appState = oldState }()

	first := hashLoginCode("+996700000000", "123456")
	second := hashLoginCode("+996700000001", "123456")
	third := hashLoginCode("+996700000000", "654321")

	if first == second {
		t.Fatal("expected hash to change when phone changes")
	}
	if first == third {
		t.Fatal("expected hash to change when code changes")
	}
}
