package httpapi

import (
	"log/slog"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/payment/obank"
)

// O!Dengi signs mktime into every result notification. A captured, validly
// signed notification must not be replayable forever, but the bank retries
// failed deliveries, so the window is generous. Unknown mktime formats are
// accepted and logged rather than rejected, so a format change on the bank
// side cannot block real payments; the order, amount and transaction checks
// in applyOBankResult still apply.
const (
	obankResultMaxAge    = 7 * 24 * time.Hour
	obankResultMaxFuture = 10 * time.Minute
)

func obankResultIsFresh(result obank.Result, now time.Time) bool {
	if result.IssuedAt.IsZero() {
		slog.Warn("obank_result_mktime_unrecognized",
			"order_id", result.OrderID,
			"mktime_length", result.RawMktimeLength,
		)
		return true
	}
	age := now.Sub(result.IssuedAt)
	if age > obankResultMaxAge || age < -obankResultMaxFuture {
		slog.Warn("obank_result_rejected_stale",
			"order_id", result.OrderID,
			"issued_at", result.IssuedAt.Format(time.RFC3339),
			"age_seconds", int64(age.Seconds()),
		)
		return false
	}
	return true
}
