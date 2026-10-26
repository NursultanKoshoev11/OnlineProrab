package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	verifyAttemptWindow     = 15 * time.Minute
	maxVerifyAttemptsPhone  = 10
	maxVerifyAttemptsRemote = 30
	authAttemptRetention    = 7 * 24 * time.Hour
	smsCodeRetention        = 24 * time.Hour
	authAttemptPruneEvery   = 6 * time.Hour
	authAttemptPruneRetry   = 15 * time.Minute
	authAttemptPruneBatch   = 5000
)

var authAttemptPruneMu sync.Mutex
var lastAuthAttemptPrune time.Time
var authAttemptPruneRunning bool

var errInvalidClientAddress = errors.New("cannot determine client IP from the configured trusted proxy")

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
		if !phoneRe.MatchString(phone) {
			phone = ""
		} else {
			phone = smsRateLimitPhone(phone)
		}

		remoteKey, err := requestRemoteKey(r)
		if err != nil {
			Error(w, http.StatusBadRequest, "invalid client address")
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		attemptID, retryAfter, err := reserveAuthAttempt(
			ctx,
			"sms_verify",
			phone,
			remoteKey,
			verifyAttemptWindow,
			maxVerifyAttemptsPhone,
			maxVerifyAttemptsRemote,
			0,
		)
		cancel()
		if err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		if retryAfter > 0 {
			w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
			Error(w, http.StatusTooManyRequests, "too many verification attempts")
			return
		}

		pruneAuthHistoryIfDue()

		recorder := &authStatusRecorder{ResponseWriter: w}
		next(recorder, r)
		completeAuthAttempt(attemptID, recorder.status >= 200 && recorder.status < 300)
	}
}

func reserveAuthAttempt(
	ctx context.Context,
	action string,
	phone string,
	remoteKey string,
	window time.Duration,
	phoneLimit int,
	remoteLimit int,
	phoneCooldown time.Duration,
) (int64, time.Duration, error) {
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx)

	lockKeys := []string{"auth-attempt:" + action + ":remote:" + remoteKey}
	if phone != "" {
		lockKeys = append(lockKeys, "auth-attempt:"+action+":phone:"+phone)
	}
	sort.Strings(lockKeys)
	for _, key := range lockKeys {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, key); err != nil {
			return 0, 0, err
		}
	}

	var phoneCount int
	var remoteCount int
	var latestPhoneAttempt time.Time
	err = tx.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE remote_key = $1),
			COUNT(*) FILTER (WHERE phone IN (NULLIF($2, ''), '+' || NULLIF($2, ''))),
			COALESCE(MAX(created_at) FILTER (WHERE phone IN (NULLIF($2, ''), '+' || NULLIF($2, ''))), to_timestamp(0))
		FROM auth_attempts
		WHERE action = $3
		  AND created_at > now() - make_interval(secs => $4)
		  AND (remote_key = $1 OR phone IN (NULLIF($2, ''), '+' || NULLIF($2, '')))
	`, remoteKey, phone, action, int(window.Seconds())).Scan(&remoteCount, &phoneCount, &latestPhoneAttempt)
	if err != nil {
		return 0, 0, err
	}

	if phoneCooldown > 0 && phone != "" && latestPhoneAttempt.Unix() > 0 {
		remaining := time.Until(latestPhoneAttempt.Add(phoneCooldown))
		if remaining > 0 {
			return 0, remaining, nil
		}
	}
	if remoteLimit > 0 && remoteCount >= remoteLimit {
		return 0, window, nil
	}
	if phoneLimit > 0 && phone != "" && phoneCount >= phoneLimit {
		return 0, window, nil
	}

	var attemptID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO auth_attempts (phone, remote_key, action, succeeded)
		VALUES (NULLIF($1, ''), $2, $3, FALSE)
		RETURNING id
	`, phone, remoteKey, action).Scan(&attemptID)
	if err != nil {
		return 0, 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, 0, err
	}
	return attemptID, 0, nil
}

func completeAuthAttempt(attemptID int64, succeeded bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, err := appState.DB.Pool.Exec(ctx, `UPDATE auth_attempts SET succeeded = $2 WHERE id = $1`, attemptID, succeeded); err != nil {
		slog.Error("sms_attempt_result_record_failed", "error", err)
	}
}

func smsRateLimitPhone(phone string) string {
	return strings.TrimPrefix(normalizePhone(phone), "+")
}

func pruneAuthHistoryIfDue() {
	pruneAuthHistoryIfDueContext(context.Background())
}

// RunAuthHistoryPruner periodically removes expired login security records,
// including when the API receives no SMS traffic.
func RunAuthHistoryPruner(ctx context.Context) {
	pruneAuthHistoryIfDueContext(ctx)
	ticker := time.NewTicker(authAttemptPruneRetry)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			pruneAuthHistoryIfDueContext(ctx)
		}
	}
}

func pruneAuthHistoryIfDueContext(parent context.Context) {
	if appState.DB == nil || appState.DB.Pool == nil {
		return
	}

	now := time.Now()
	authAttemptPruneMu.Lock()
	if authAttemptPruneRunning || (!lastAuthAttemptPrune.IsZero() && now.Sub(lastAuthAttemptPrune) < authAttemptPruneEvery) {
		authAttemptPruneMu.Unlock()
		return
	}
	authAttemptPruneRunning = true
	authAttemptPruneMu.Unlock()

	ctx, cancel := context.WithTimeout(parent, 5*time.Second)
	defer cancel()
	err := pruneAuthHistory(ctx)

	authAttemptPruneMu.Lock()
	authAttemptPruneRunning = false
	if err == nil {
		lastAuthAttemptPrune = now
	}
	authAttemptPruneMu.Unlock()

	if err != nil {
		slog.Error("auth_history_prune_failed", "error", err)
	}
}

func pruneAuthHistory(ctx context.Context) error {
	if err := deleteExpiredAuthRows(ctx, `
		DELETE FROM auth_attempts
		WHERE id IN (
			SELECT id FROM auth_attempts
			WHERE created_at < now() - make_interval(secs => $1)
			ORDER BY id
			LIMIT $2
		)
	`, authAttemptRetention); err != nil {
		return fmt.Errorf("auth attempts: %w", err)
	}
	if err := deleteExpiredAuthRows(ctx, `
		DELETE FROM sms_login_codes
		WHERE id IN (
			SELECT id FROM sms_login_codes
			WHERE expires_at < now() - make_interval(secs => $1)
			ORDER BY expires_at
			LIMIT $2
		)
	`, smsCodeRetention); err != nil {
		return fmt.Errorf("SMS login codes: %w", err)
	}
	return nil
}

func deleteExpiredAuthRows(ctx context.Context, query string, retention time.Duration) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		result, err := appState.DB.Pool.Exec(ctx, query, int(retention.Seconds()), authAttemptPruneBatch)
		if err != nil {
			return err
		}
		if result.RowsAffected() < authAttemptPruneBatch {
			return nil
		}
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

func requestRemoteKey(r *http.Request) (string, error) {
	remoteAddr, err := parseRemoteAddress(r.RemoteAddr)
	if err != nil {
		return "", err
	}
	if !isTrustedProxy(remoteAddr) {
		return remoteAddr.String(), nil
	}

	var forwarded []netip.Addr
	for _, header := range r.Header.Values("X-Forwarded-For") {
		for _, value := range strings.Split(header, ",") {
			addr, err := netip.ParseAddr(strings.TrimSpace(value))
			if err != nil || addr.Zone() != "" {
				return "", errInvalidClientAddress
			}
			forwarded = append(forwarded, addr.Unmap())
		}
	}
	if len(forwarded) == 0 {
		return "", errInvalidClientAddress
	}

	forwarded = append(forwarded, remoteAddr)
	for i := len(forwarded) - 1; i >= 0; i-- {
		if !isTrustedProxy(forwarded[i]) {
			return forwarded[i].String(), nil
		}
	}
	return "", errInvalidClientAddress
}

func parseRemoteAddress(remoteAddr string) (netip.Addr, error) {
	value := strings.TrimSpace(remoteAddr)
	if host, _, err := net.SplitHostPort(value); err == nil {
		value = host
	}
	addr, err := netip.ParseAddr(value)
	if err != nil {
		return netip.Addr{}, errInvalidClientAddress
	}
	return addr.WithZone("").Unmap(), nil
}

func isTrustedProxy(addr netip.Addr) bool {
	for _, value := range appState.TrustedProxyCIDRs {
		value = strings.TrimSpace(value)
		if prefix, err := netip.ParsePrefix(value); err == nil {
			if prefix.Masked().Contains(addr) {
				return true
			}
			continue
		}
		if proxyAddr, err := netip.ParseAddr(value); err == nil && proxyAddr.Unmap() == addr {
			return true
		}
	}
	return false
}
