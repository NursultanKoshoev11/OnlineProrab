package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSecurityHeadersAreApplied(t *testing.T) {
	previousState := appState
	appState.IsProductionLike = true
	t.Cleanup(func() { appState = previousState })

	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	checks := map[string]string{
		"X-Content-Type-Options":    "nosniff",
		"X-Frame-Options":           "DENY",
		"Referrer-Policy":           "no-referrer",
		"Permissions-Policy":        "camera=(), microphone=(), geolocation=()",
		"Cache-Control":             "no-store",
		"Strict-Transport-Security": "max-age=31536000",
	}
	for header, expected := range checks {
		if got := rec.Header().Get(header); got != expected {
			t.Fatalf("expected %s=%q, got %q", header, expected, got)
		}
	}
}

func TestSecurityHeadersOmitHSTSInDevelopment(t *testing.T) {
	previousState := appState
	appState.IsProductionLike = false
	t.Cleanup(func() { appState = previousState })

	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	if got := rec.Header().Get("Strict-Transport-Security"); got != "" {
		t.Fatalf("expected no HSTS header in development, got %q", got)
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

func TestRequestIDReplacesUnsafeClientValue(t *testing.T) {
	handler := withMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("X-Request-ID", "request id with spaces")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-ID"); got == "request id with spaces" || got == "" {
		t.Fatalf("expected unsafe request id to be replaced, got %q", got)
	}
}

func TestRequestLoggerRecordsRecoveredPanicWithoutPanicValue(t *testing.T) {
	previousLogger := slog.Default()
	var output bytes.Buffer
	slog.SetDefault(slog.New(slog.NewJSONHandler(&output, nil)))
	t.Cleanup(func() { slog.SetDefault(previousLogger) })

	handler := withMiddleware(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("sensitive panic value")
	}))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected status 500 after panic recovery, got %d", rec.Code)
	}
	if strings.Contains(output.String(), "sensitive panic value") {
		t.Fatalf("panic value should not be written to logs: %q", output.String())
	}

	foundRequestEvent := false
	for _, line := range strings.Split(strings.TrimSpace(output.String()), "\n") {
		var event map[string]any
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			t.Fatalf("expected JSON log record, got %q: %v", line, err)
		}
		if event["msg"] == "http_request" &&
			event["status"] == float64(http.StatusInternalServerError) &&
			event["level"] == "ERROR" {
			foundRequestEvent = true
		}
	}
	if !foundRequestEvent {
		t.Fatalf("expected a request event for the recovered 500 response, got %q", output.String())
	}
}

func TestRequestLoggerUsesRoutePatternWithoutPathValues(t *testing.T) {
	previousLogger := slog.Default()
	var output bytes.Buffer
	slog.SetDefault(slog.New(slog.NewJSONHandler(&output, nil)))
	t.Cleanup(func() { slog.SetDefault(previousLogger) })

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/files/{fileID}", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	handler := withMiddleware(mux)
	pathValue := "private-file-id-123"
	req := httptest.NewRequest(http.MethodGet, "/api/v1/files/"+pathValue, nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if strings.Contains(output.String(), pathValue) {
		t.Fatalf("request path value must not appear in logs: %q", output.String())
	}
	if !strings.Contains(output.String(), `"route":"GET /api/v1/files/{fileID}"`) {
		t.Fatalf("expected a parameter-free route pattern in logs, got %q", output.String())
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
