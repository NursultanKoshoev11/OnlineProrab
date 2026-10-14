package httpapi

import (
	"net/http/httptest"
	"testing"
)

func TestRequestRemoteKeyIgnoresForwardedHeaderFromUntrustedPeer(t *testing.T) {
	oldState := appState
	defer func() { appState = oldState }()
	appState.TrustedProxyCIDRs = []string{"10.20.0.0/16"}

	req := httptest.NewRequest("POST", "/", nil)
	req.RemoteAddr = "198.51.100.10:4567"
	req.Header.Set("X-Forwarded-For", "203.0.113.99")

	got, err := requestRemoteKey(req)
	if err != nil {
		t.Fatalf("resolve remote key: %v", err)
	}
	if got != "198.51.100.10" {
		t.Fatalf("expected the socket peer to be used, got %q", got)
	}
}

func TestRequestRemoteKeyWalksTrustedProxyChainFromTheRight(t *testing.T) {
	oldState := appState
	defer func() { appState = oldState }()
	appState.TrustedProxyCIDRs = []string{"10.20.0.0/16"}

	req := httptest.NewRequest("POST", "/", nil)
	req.RemoteAddr = "10.20.1.2:443"
	req.Header.Set("X-Forwarded-For", "203.0.113.200, 198.51.100.50")

	got, err := requestRemoteKey(req)
	if err != nil {
		t.Fatalf("resolve remote key: %v", err)
	}
	if got != "198.51.100.50" {
		t.Fatalf("expected the first untrusted hop from the right, got %q", got)
	}
}

func TestRequestRemoteKeyRejectsMissingOrMalformedForwardedAddressFromTrustedProxy(t *testing.T) {
	oldState := appState
	defer func() { appState = oldState }()
	appState.TrustedProxyCIDRs = []string{"10.20.0.0/16"}

	for _, forwarded := range []string{"", "not-an-ip", "10.20.3.4, 10.20.5.6"} {
		t.Run(forwarded, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/", nil)
			req.RemoteAddr = "10.20.1.2:443"
			if forwarded != "" {
				req.Header.Set("X-Forwarded-For", forwarded)
			}

			if _, err := requestRemoteKey(req); err == nil {
				t.Fatal("expected trusted proxy request without a valid client address to be rejected")
			}
		})
	}
}
