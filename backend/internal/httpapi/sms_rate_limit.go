package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	smsRequestCooldown          = 45 * time.Second
	smsHourlyLimit              = 6
	smsRequestRemoteHourlyLimit = 30
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
		phone = smsRateLimitPhone(phone)

		remoteKey, err := requestRemoteKey(r)
		if err != nil {
			Error(w, http.StatusBadRequest, "invalid client address")
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		attemptID, retryAfter, err := reserveAuthAttempt(
			ctx,
			"sms_request",
			phone,
			remoteKey,
			time.Hour,
			smsHourlyLimit,
			smsRequestRemoteHourlyLimit,
			smsRequestCooldown,
		)
		cancel()
		if err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		if retryAfter > 0 {
			retrySeconds := int(retryAfter.Seconds())
			if retrySeconds < 1 {
				retrySeconds = 1
			}
			w.Header().Set("Retry-After", strconv.Itoa(retrySeconds))
			Error(w, http.StatusTooManyRequests, "too many code requests")
			return
		}
		pruneAuthHistoryIfDue()

		recorder := &authStatusRecorder{ResponseWriter: w}
		next(recorder, r)
		completeAuthAttempt(attemptID, recorder.status >= 200 && recorder.status < 300)
	}
}
