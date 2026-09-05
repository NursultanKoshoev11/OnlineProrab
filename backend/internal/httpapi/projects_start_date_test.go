package httpapi

import (
	"testing"
	"time"
)

func TestNormalizeProjectStartDate(t *testing.T) {
	t.Run("valid date", func(t *testing.T) {
		got, err := normalizeProjectStartDate("2026-09-01", true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "2026-09-01" {
			t.Fatalf("got %q, want 2026-09-01", got)
		}
	})

	t.Run("invalid format", func(t *testing.T) {
		if _, err := normalizeProjectStartDate("01.09.2026", true); err == nil {
			t.Fatal("expected invalid date format error")
		}
	})

	t.Run("optional empty update", func(t *testing.T) {
		got, err := normalizeProjectStartDate("", false)
		if err != nil || got != "" {
			t.Fatalf("got %q, err %v; want empty value without error", got, err)
		}
	})

	t.Run("empty create falls back to today", func(t *testing.T) {
		got, err := normalizeProjectStartDate("", true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if _, err := time.Parse("2006-01-02", got); err != nil {
			t.Fatalf("fallback is not an ISO date: %q", got)
		}
	})
}
