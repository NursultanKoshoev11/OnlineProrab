package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

const (
	verifyAttemptWindow      = 15 * time.Minute
	maxVerifyAttemptsPhone  = 10
	maxVerifyAttemptsRemote = 30
	authAttemptRetention    = 7 * 24 * time.Hour
	smsCodeRetention        = 24 * time.Hour
)

func withSMSVerifyRateLimit(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			next(w, r)
			return
		}
		if appState.DB == nil || appState.DB.Pool == nil {
			Error(w, http.StatusServiceUnavailable, "database is not available")
			return
		}

		body, err := io.ReadAll(io.LimitReader(r.Body, 64<<10))
		if err != nil {
			Error(w, http.StatusBadRequest, "invalid request body")
			return
		}
		r.Body = io.NopCloser(bytes.NewReader(body))

		var payload verifySMSCodeRequest
		if err := json.Unmarshal(body, &payload); err != nil {
			Error(w, http.StatusBadRequest, "invalid JSON body")
			return
		}
		phone := normalizePhone(payload.Phone)
		remoteKey := requestRemoteKey(r)

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		_, _ = appState.DB.Pool.Exec(ctx, `
			DELETE FROM auth_attempts
			WHERE created_at < now() - make_interval(secs => $1)
		`, int(authAttemptRetention.Seconds()))
		_, _ = appState.DB.Pool.Exec(ctx, `
			DELETE FROM sms_login_codes
			WHERE created_at < now() - make_interval(secs => $1)
		`, int(smsCodeRetention.Seconds()))

		var phoneFailures int
		var remoteFailures int
		err = appState.DB.Pool.QueryRow(ctx, `
			SELECT
				COUNT(*) FILTER (
					WHERE phone = $1
					  AND action = 'sms_verify'
					  AND succeeded = FALSE
					  AND created_at > now() - make_interval(secs => $3)
				),
				COUNT(*) FILTER (
					WHERE remote_key = $2
					  AND action = 'sms_verify'
					  AND succeeded = FALSE
					  AND created_at > now() - make_interval(secs => $3)
				)
			FROM auth_attempts
		`, phone, remoteKey, int(verifyAttemptWindow.Seconds())).Scan(&phoneFailures, &remoteFailures)
		if err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		if phoneFailures >= maxVerifyAttemptsPhone || remoteFailures >= maxVerifyAttemptsRemote {
			w.Header().Set("Retry-After", "900")
			Error(w, http.StatusTooManyRequests, "too many verification attempts")
			return
		}

		recorder := &authStatusRecorder{ResponseWriter: w}
		next(recorder, r)
		succeeded := recorder.status >= 200 && recorder.status < 300
		writeCtx, writeCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer writeCancel()
		_, _ = appState.DB.Pool.Exec(writeCtx, `
			INSERT INTO auth_attempts (phone, remote_key, action, succeeded)
			VALUES (NULLIF($1, ''), $2, 'sms_verify', $3)
		`, phone, remoteKey, succeeded)
	}
}

type authStatusRecorder struct {
	http.ResponseWriter
	status int
}

func (w *authStatusRecorder) WriteHeader(status int) {
	if w.status != 0 {
		return
	}
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *authStatusRecorder) Write(body []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

func requestRemoteKey(r *http.Request) string {
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err == nil && host != "" {
		return host
	}
	if value := strings.TrimSpace(r.RemoteAddr); value != "" {
		return value
	}
	return "unknown"
}
