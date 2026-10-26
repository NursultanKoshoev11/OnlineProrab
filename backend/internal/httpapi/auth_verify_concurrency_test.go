package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestVerifySMSCodeConsumesAnOTPOnlyOnceUnderConcurrency(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{
		DB:             db,
		JWTSecret:      "sms-concurrency-test-signing-key-1234567890",
		AccessTokenTTL: 15 * time.Minute,
	}

	const phone = "+996700000101"
	const code = "123456"
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, now() + interval '5 minutes')
	`, phone, hashLoginCode(phone, code)); err != nil {
		t.Fatalf("seed SMS login code: %v", err)
	}

	const requestCount = 8
	results := make(chan int, requestCount)
	var requests sync.WaitGroup
	for i := 0; i < requestCount; i++ {
		requests.Add(1)
		go func() {
			defer requests.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/verify", strings.NewReader(fmt.Sprintf(`{"phone":%q,"code":%q}`, phone, code)))
			rec := httptest.NewRecorder()
			VerifySMSCode(rec, req)
			results <- rec.Code
		}()
	}
	requests.Wait()
	close(results)

	var verified int
	var rejected int
	for status := range results {
		switch status {
		case http.StatusOK:
			verified++
		case http.StatusUnauthorized:
			rejected++
		default:
			t.Errorf("unexpected verification status %d", status)
		}
	}
	if verified != 1 || rejected != requestCount-1 {
		t.Fatalf("expected one successful and %d rejected OTP uses, got %d successful and %d rejected", requestCount-1, verified, rejected)
	}
}

func TestVerifySMSCodeSerializesWrongCodeAttemptCounter(t *testing.T) {
	db := openSMSAuthTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{
		DB:             db,
		JWTSecret:      "sms-concurrency-test-signing-key-1234567890",
		AccessTokenTTL: 15 * time.Minute,
	}

	const phone = "+996700000102"
	const code = "123456"
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, now() + interval '5 minutes')
	`, phone, hashLoginCode(phone, code)); err != nil {
		t.Fatalf("seed SMS login code: %v", err)
	}

	const requestCount = 10
	results := make(chan int, requestCount)
	var requests sync.WaitGroup
	for i := 0; i < requestCount; i++ {
		requests.Add(1)
		go func() {
			defer requests.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/sms/verify", strings.NewReader(fmt.Sprintf(`{"phone":%q,"code":"654321"}`, phone)))
			rec := httptest.NewRecorder()
			VerifySMSCode(rec, req)
			results <- rec.Code
		}()
	}
	requests.Wait()
	close(results)

	var invalid int
	var limited int
	for status := range results {
		switch status {
		case http.StatusUnauthorized:
			invalid++
		case http.StatusTooManyRequests:
			limited++
		default:
			t.Errorf("unexpected verification status %d", status)
		}
	}
	if invalid != 5 || limited != requestCount-5 {
		t.Fatalf("expected five invalid attempts and %d locked attempts, got %d invalid and %d locked", requestCount-5, invalid, limited)
	}

	var attempts int
	if err := db.Pool.QueryRow(context.Background(), `SELECT attempts FROM sms_login_codes WHERE phone = $1`, phone).Scan(&attempts); err != nil {
		t.Fatalf("read code attempts: %v", err)
	}
	if attempts != 5 {
		t.Fatalf("expected code attempt counter to stop at 5, got %d", attempts)
	}
}
