package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func TestSMSRequestRateLimitAtomicallyCapsOneSourceAcrossPhoneNumbers(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db}

	var accepted atomic.Int32
	handler := withSMSRequestRateLimit(func(w http.ResponseWriter, _ *http.Request) {
		accepted.Add(1)
		w.WriteHeader(http.StatusAccepted)
	})

	const requestCount = smsRequestRemoteHourlyLimit * 2
	results := make(chan int, requestCount)
	var requests sync.WaitGroup
	for i := 0; i < requestCount; i++ {
		requests.Add(1)
		go func(index int) {
			defer requests.Done()
			body := fmt.Sprintf(`{"phone":"+996700%06d"}`, index+1)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/request", strings.NewReader(body))
			req.RemoteAddr = "198.51.100.42:43210"
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			results <- rec.Code
		}(i)
	}
	requests.Wait()
	close(results)

	var acceptedResponses int
	var limitedResponses int
	for status := range results {
		switch status {
		case http.StatusAccepted:
			acceptedResponses++
		case http.StatusTooManyRequests:
			limitedResponses++
		default:
			t.Errorf("unexpected response status %d", status)
		}
	}
	if acceptedResponses != smsRequestRemoteHourlyLimit || accepted.Load() != int32(smsRequestRemoteHourlyLimit) {
		t.Fatalf("expected exactly %d requests to reach the sender, got %d responses and %d handler calls", smsRequestRemoteHourlyLimit, acceptedResponses, accepted.Load())
	}
	if limitedResponses != requestCount-smsRequestRemoteHourlyLimit {
		t.Fatalf("expected %d source-limit responses, got %d", requestCount-smsRequestRemoteHourlyLimit, limitedResponses)
	}
}

func TestSMSRequestRateLimitEnforcesPerPhoneHourlyLimit(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db}

	const phone = "+996700000001"
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO auth_attempts (phone, remote_key, action, succeeded, created_at)
		SELECT $1, '198.51.100.8', 'sms_request', TRUE, now() - interval '1 minute'
	FROM generate_series(1, $2)
	`, phone, smsHourlyLimit); err != nil {
		t.Fatalf("seed previous SMS requests: %v", err)
	}

	handlerCalls := 0
	handler := withSMSRequestRateLimit(func(w http.ResponseWriter, _ *http.Request) {
		handlerCalls++
		w.WriteHeader(http.StatusAccepted)
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/request", strings.NewReader(`{"phone":"+996700000001"}`))
	req.RemoteAddr = "198.51.100.9:43210"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected phone hourly limit to return 429, got %d: %s", rec.Code, rec.Body.String())
	}
	if handlerCalls != 0 {
		t.Fatalf("limited request reached SMS handler %d times", handlerCalls)
	}
}
