package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	smsRequestCooldown = 45 * time.Second
	smsHourlyLimit     = 6
)

func withSMSRequestRateLimit(next http.HandlerFunc) http.HandlerFunc {
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

		var payload struct {
			Phone string `json:"phone"`
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			Error(w, http.StatusBadRequest, "invalid JSON body")
			return
		}
		phone := normalizePhone(strings.TrimSpace(payload.Phone))
		if !phoneRe.MatchString(phone) {
			next(w, r)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		var latestCreatedAt time.Time
		var hourlyCount int
		err = appState.DB.Pool.QueryRow(ctx, `
			SELECT COALESCE(MAX(created_at), to_timestamp(0)),
			       COUNT(*) FILTER (WHERE created_at > now() - interval '1 hour')
			FROM sms_login_codes
			WHERE phone = $1
		`, phone).Scan(&latestCreatedAt, &hourlyCount)
		if err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		if latestCreatedAt.Unix() > 0 && time.Since(latestCreatedAt) < smsRequestCooldown {
			w.Header().Set("Retry-After", "45")
			Error(w, http.StatusTooManyRequests, "please wait before requesting another code")
			return
		}
		if hourlyCount >= smsHourlyLimit {
			w.Header().Set("Retry-After", "3600")
			Error(w, http.StatusTooManyRequests, "too many code requests")
			return
		}

		next(w, r.WithContext(ctx))
	}
}
