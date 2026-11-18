package httpapi

import (
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/payment/obank"
)

func TestOBankResultFreshnessWindow(t *testing.T) {
	now := time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		name     string
		issuedAt time.Time
		want     bool
	}{
		{"just issued", now.Add(-time.Minute), true},
		{"bank retry after a day", now.Add(-24 * time.Hour), true},
		{"replayed after the window", now.Add(-obankResultMaxAge - time.Minute), false},
		{"small clock skew", now.Add(5 * time.Minute), true},
		{"issued in the future", now.Add(obankResultMaxFuture + time.Minute), false},
		{"unknown mktime format is not rejected", time.Time{}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := obankResultIsFresh(obank.Result{OrderID: "stroy_order-1", IssuedAt: tc.issuedAt}, now)
			if got != tc.want {
				t.Fatalf("obankResultIsFresh() = %v, want %v", got, tc.want)
			}
		})
	}
}
