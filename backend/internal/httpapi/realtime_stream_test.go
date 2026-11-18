package httpapi

import (
	"bufio"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRealtimeStreamOutlivesServerWriteTimeout(t *testing.T) {
	previousKeepAlive, previousWriteTimeout := realtimeKeepAliveInterval, realtimeWriteTimeout
	realtimeKeepAliveInterval = 50 * time.Millisecond
	realtimeWriteTimeout = 250 * time.Millisecond
	defer func() {
		realtimeKeepAliveInterval, realtimeWriteTimeout = previousKeepAlive, previousWriteTimeout
	}()

	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r = r.WithContext(withUserID(r.Context(), "realtime-stream-test-user"))
		RealtimeEvents(w, r)
	})
	server := httptest.NewUnstartedServer(withMiddleware(handler))
	// Production uses a 30s WriteTimeout; scale it down with the stream timings.
	server.Config.WriteTimeout = 200 * time.Millisecond
	server.Start()
	defer server.Close()

	response, err := http.Get(server.URL)
	if err != nil {
		t.Fatalf("open stream: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("stream status = %d", response.StatusCode)
	}

	reader := bufio.NewReader(response.Body)
	deadline := time.Now().Add(800 * time.Millisecond)
	keepAlives := 0
	for time.Now().Before(deadline) {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("stream closed after %d keep-alives (server WriteTimeout cut it): %v", keepAlives, err)
		}
		if strings.HasPrefix(line, ": keep-alive") {
			keepAlives++
		}
	}
	if keepAlives < 5 {
		t.Fatalf("expected the stream to keep sending keep-alives past the write timeout, got %d", keepAlives)
	}
}
