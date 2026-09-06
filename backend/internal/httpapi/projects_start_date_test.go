package httpapi

import (
	"math"
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

func TestNormalizeISODate(t *testing.T) {
	got, err := normalizeISODate("2026-09-06", false, "due_date")
	if err != nil || got != "2026-09-06" {
		t.Fatalf("valid date = %q, %v; want 2026-09-06", got, err)
	}
	if _, err := normalizeISODate("06.09.2026", false, "report_date"); err == nil {
		t.Fatal("expected invalid ISO date to be rejected")
	}
	got, err = normalizeISODate("", true, "report_date")
	if err != nil {
		t.Fatalf("empty date fallback returned error: %v", err)
	}
	if _, err := time.Parse("2006-01-02", got); err != nil {
		t.Fatalf("fallback is not an ISO date: %q", got)
	}
}

func TestProjectBudgetValidation(t *testing.T) {
	for _, value := range []float64{0, 1, 250000.5, maxMoneyAmount} {
		if err := validateProjectBudget(value); err != nil {
			t.Errorf("validateProjectBudget(%v) returned error: %v", value, err)
		}
	}

	for _, value := range []float64{-1, math.Inf(1), maxMoneyAmount + 1, maxMoneyAmount + 0.001} {
		if err := validateProjectBudget(value); err == nil {
			t.Errorf("validateProjectBudget(%v) accepted invalid value", value)
		}
	}
}

func TestNormalizeProjectCurrency(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{input: "", want: "KGS"},
		{input: " usd ", want: "USD"},
		{input: "KZT", want: "KZT"},
	}
	for _, test := range cases {
		got, err := normalizeProjectCurrency(test.input)
		if err != nil || got != test.want {
			t.Errorf("normalizeProjectCurrency(%q) = %q, %v; want %q", test.input, got, err, test.want)
		}
	}
	if _, err := normalizeProjectCurrency("EUR"); err == nil {
		t.Fatal("expected unsupported currency to be rejected")
	}
}

func TestNormalizeCostItemRequest(t *testing.T) {
	req := createCostItemRequest{
		Title:    "  Цемент  ",
		Currency: " usd ",
		SpentAt:  "2026-09-05",
	}
	if err := normalizeCostItemRequest(&req); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if req.Title != "Цемент" || req.Currency != "USD" || req.SpentAt != "2026-09-05" {
		t.Fatalf("normalized request = %+v", req)
	}

	for _, test := range []createCostItemRequest{
		{Currency: "EUR"},
		{SpentAt: "05.09.2026"},
		{Amount: maxMoneyAmount + 1},
	} {
		if err := normalizeCostItemRequest(&test); err == nil {
			t.Errorf("normalizeCostItemRequest(%+v) accepted invalid input", test)
		}
	}
}

func TestPartialUpdateNormalizationPreservesMissingDates(t *testing.T) {
	cost := createCostItemRequest{Title: "Материалы", Amount: 10}
	if err := normalizeCostItemUpdateRequest(&cost); err != nil {
		t.Fatalf("normalizeCostItemUpdateRequest returned error: %v", err)
	}
	if cost.SpentAt != "" {
		t.Fatalf("missing cost date became %q; want empty for SQL COALESCE", cost.SpentAt)
	}

	report := createDailyReportRequest{Summary: "Работы", WorkersCount: 1}
	if err := normalizeDailyReportUpdateRequest(&report); err != nil {
		t.Fatalf("normalizeDailyReportUpdateRequest returned error: %v", err)
	}
	if report.ReportDate != "" {
		t.Fatalf("missing report date became %q; want empty for SQL COALESCE", report.ReportDate)
	}
}

func TestWorkersCountValidation(t *testing.T) {
	for _, value := range []int{0, 1, maxWorkersCount} {
		if !isValidWorkersCount(value) {
			t.Errorf("isValidWorkersCount(%d) rejected valid value", value)
		}
	}
	for _, value := range []int{-1, maxWorkersCount + 1} {
		if isValidWorkersCount(value) {
			t.Errorf("isValidWorkersCount(%d) accepted invalid value", value)
		}
	}
}
