package httpapi

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSecurityHeadersAreApplied(t *testing.T) {
	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	checks := map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "no-referrer",
		"Cache-Control":          "no-store",
	}
	for header, expected := range checks {
		if got := rec.Header().Get(header); got != expected {
			t.Fatalf("expected %s=%q, got %q", header, expected, got)
		}
	}
}

func TestRequestIDIsGeneratedAndExposed(t *testing.T) {
	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if requestIDFromContext(r.Context()) == "" {
			t.Fatal("expected request id in context")
		}
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-ID"); got == "" {
		t.Fatal("expected X-Request-ID response header")
	}
}

func TestRequestIDPreservesValidClientValue(t *testing.T) {
	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("X-Request-ID", "client-request-123")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-ID"); got != "client-request-123" {
		t.Fatalf("expected client request id, got %q", got)
	}
}

func TestBodyLimitRejectsOversizedJSON(t *testing.T) {
	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusRequestEntityTooLarge)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))

	body := bytes.NewBufferString(strings.Repeat("a", int(maxJSONBodyBytes)+1))
	req := httptest.NewRequest(http.MethodPost, "/api/v1/projects", body)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected status 413, got %d", rec.Code)
	}
}

func TestCORSMiddlewareAllowsConfiguredOrigin(t *testing.T) {
	oldOrigins := corsAllowedOrigins
	SetCORSAllowedOrigins([]string{"https://app.example.com"})
	defer SetCORSAllowedOrigins(oldOrigins)

	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/projects", nil)
	req.Header.Set("Origin", "https://app.example.com")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://app.example.com" {
		t.Fatalf("expected CORS origin header, got %q", got)
	}
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected status 204, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Expose-Headers"); got != "X-Request-ID" {
		t.Fatalf("expected exposed request id header, got %q", got)
	}
}
