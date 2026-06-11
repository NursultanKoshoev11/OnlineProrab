package httpapi

import "testing"

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
