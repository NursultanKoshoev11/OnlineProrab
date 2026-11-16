package httpapi

import (
	"context"
	"net/http"
	"strconv"
	"time"
)

const (
	publicSupportRequestWindow = time.Hour
	publicSupportRequestLimit  = 5
)

func withPublicSupportRateLimit(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			next(w, r)
			return
		}
		if appState.DB == nil || appState.DB.Pool == nil {
			Error(w, http.StatusServiceUnavailable, "support is temporarily unavailable")
			return
		}

		remoteKey, err := requestRemoteKey(r)
		if err != nil {
			Error(w, http.StatusBadRequest, "invalid client address")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		_, retryAfter, err := reserveAuthAttempt(
			ctx,
			"public_support",
			"",
			remoteKey,
			publicSupportRequestWindow,
			0,
			publicSupportRequestLimit,
			0,
		)
		cancel()
		if err != nil {
			Error(w, http.StatusServiceUnavailable, "support is temporarily unavailable")
			return
		}
		if retryAfter > 0 {
			retrySeconds := int(retryAfter.Seconds())
			if retrySeconds < 1 {
				retrySeconds = 1
			}
			w.Header().Set("Retry-After", strconv.Itoa(retrySeconds))
			Error(w, http.StatusTooManyRequests, "too many support requests")
			return
		}
		pruneAuthHistoryIfDue()
		next(w, r)
	}
}
