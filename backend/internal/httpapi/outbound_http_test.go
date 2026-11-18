package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestOutboundHTTPClientDoesNotFollowRedirects(t *testing.T) {
	redirectTargetHit := make(chan struct{}, 1)
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		redirectTargetHit <- struct{}{}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer target.Close()

	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer redirect.Close()

	response, err := newOutboundHTTPClient(time.Second).Get(redirect.URL)
	if err != nil {
		t.Fatalf("GET redirecting provider: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusTemporaryRedirect {
		t.Fatalf("status=%d, want %d", response.StatusCode, http.StatusTemporaryRedirect)
	}
	select {
	case <-redirectTargetHit:
		t.Fatal("outbound client followed a redirect")
	default:
	}
}

func TestSupportTransportFailureDoesNotExposeEndpoint(t *testing.T) {
	const secretPath = "/bot-should-never-be-persisted/sendMessage"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, secretPath, http.StatusTemporaryRedirect)
	}))
	defer server.Close()

	err := postSupportJSON(t.Context(), server.URL+secretPath, "", map[string]string{"text": "test"})
	if err == nil {
		t.Fatal("expected redirected support request to fail")
	}
	if strings.Contains(err.Error(), "should-never-be-persisted") || strings.Contains(err.Error(), secretPath) {
		t.Fatalf("support error exposes endpoint data: %v", err)
	}
}
