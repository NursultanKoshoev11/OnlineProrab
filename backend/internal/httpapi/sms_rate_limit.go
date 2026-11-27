package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	smsRequestCooldown          = 45 * time.Second
	smsHourlyLimit              = 6
	smsRequestRemoteHourlyLimit = 30
	smsDailyBudgetWindow        = 24 * time.Hour
	// Login SMS are only sent to Kyrgyz numbers: the service is local and
	// foreign or premium-rate destinations are the usual SMS-pumping target.
	smsSupportedCountryPrefix = "+996"
	fallbackSMSDailyLimit     = 300
	// Numbers without an account (new sign-ups, and anything an attacker
	// sprays) may use only this share of the daily budget. The rest stays
	// available to existing users, so a flood of fake sign-ups cannot lock
	// every customer out of login for a day.
	smsNewNumberBudgetPercent = 70
)

func smsDailyLimit() int {
	if appState.SMSDailyLimit > 0 {
		return appState.SMSDailyLimit
	}
	return fallbackSMSDailyLimit
}

// smsDailyBudgetExhausted reports whether the provider already delivered the
// share of the daily login-code budget available to this phone number.
func smsDailyBudgetExhausted(parent context.Context, phone string) (bool, error) {
	ctx, cancel := context.WithTimeout(parent, 3*time.Second)
	defer cancel()
	var sent int
	var registered bool
	if err := appState.DB.Pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM auth_attempts
			 WHERE action = 'sms_request'
			   AND succeeded
			   AND created_at > now() - make_interval(secs => $1)),
			EXISTS (SELECT 1 FROM users WHERE phone = $2)
	`, int(smsDailyBudgetWindow.Seconds()), phone).Scan(&sent, &registered); err != nil {
		return false, err
	}
	limit := smsDailyLimit()
	if sent == limit/2 {
		slog.Warn("sms_daily_budget_half_used", "sent", sent, "limit", limit)
	}
	if !registered {
		limit = limit * smsNewNumberBudgetPercent / 100
	}
	return sent >= limit, nil
}

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
