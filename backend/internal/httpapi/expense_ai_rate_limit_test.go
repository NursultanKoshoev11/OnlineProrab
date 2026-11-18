package httpapi

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestReserveExpenseAISearchEnforcesHourlyPerUserLimit(t *testing.T) {
	ctx := context.Background()
	userID := setupExpenseAIRateLimitTest(t, ctx)

	for attempt := 1; attempt <= maxExpenseAISearchesPerUser; attempt++ {
		retryAfter, err := reserveExpenseAISearch(ctx, userID)
		if err != nil || retryAfter != 0 {
			t.Fatalf("attempt %d: retry=%d error=%v", attempt, retryAfter, err)
		}
	}
	retryAfter, err := reserveExpenseAISearch(ctx, userID)
	if err != nil {
		t.Fatalf("reserve over-limit search: %v", err)
	}
	if retryAfter < 1 || retryAfter > int(expenseAISearchWindow/time.Second) {
		t.Fatalf("Retry-After=%d is out of range", retryAfter)
	}

	otherUserID := insertExpenseAIRateLimitTestUser(t, ctx)
	if retryAfter, err := reserveExpenseAISearch(ctx, otherUserID); err != nil || retryAfter != 0 {
		t.Fatalf("one user's quota affected another: retry=%d error=%v", retryAfter, err)
	}
}

func TestReserveExpenseAISearchIsAtomicAcrossConcurrentRequests(t *testing.T) {
	ctx := context.Background()
	userID := setupExpenseAIRateLimitTest(t, ctx)
	const requests = maxExpenseAISearchesPerUser * 2
	type result struct {
		retryAfter int
		err        error
	}
	results := make(chan result, requests)
	var group sync.WaitGroup
	for i := 0; i < requests; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			retryAfter, err := reserveExpenseAISearch(ctx, userID)
			results <- result{retryAfter: retryAfter, err: err}
		}()
	}
	group.Wait()
	close(results)

	var allowed, limited int
	for item := range results {
		if item.err != nil {
			t.Fatalf("reserve concurrent search: %v", item.err)
		}
		if item.retryAfter == 0 {
			allowed++
		} else {
			limited++
		}
	}
	if allowed != maxExpenseAISearchesPerUser || limited != requests-maxExpenseAISearchesPerUser {
		t.Fatalf("allowed=%d limited=%d", allowed, limited)
	}
}

func TestExpenseAIAnalysisHasBoundedSample(t *testing.T) {
	items := make([]CostItemDTO, maxExpenseAIItemsPerSearch+5)
	limited, truncated := expenseAIItemsForAnalysis(items)
	if len(limited) != maxExpenseAIItemsPerSearch || !truncated {
		t.Fatalf("got len=%d truncated=%t", len(limited), truncated)
	}
	complete, truncated := expenseAIItemsForAnalysis(items[:maxExpenseAIItemsPerSearch])
	if len(complete) != maxExpenseAIItemsPerSearch || truncated {
		t.Fatalf("got len=%d truncated=%t for complete input", len(complete), truncated)
	}
}

func TestValidateExpenseAISearchRange(t *testing.T) {
	tests := []struct {
		name    string
		from    string
		to      string
		wantErr bool
	}{
		{name: "unbounded", wantErr: false},
		{name: "valid month", from: "2026-05-01", to: "2026-06-01"},
		{name: "missing end", from: "2026-05-01", wantErr: true},
		{name: "invalid date", from: "2026-02-30", to: "2026-03-01", wantErr: true},
		{name: "reversed", from: "2026-06-01", to: "2026-05-01", wantErr: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			from, to, err := validateExpenseAISearchRange(test.from, test.to)
			if (err != nil) != test.wantErr {
				t.Fatalf("validate range returned %q, %q, %v", from, to, err)
			}
			if err == nil && (from != test.from || to != test.to) {
				t.Fatalf("normalized range is %q to %q", from, to)
			}
		})
	}
}

func TestAuthHistoryPrunerRemovesExpiredExpenseAISearchAttempts(t *testing.T) {
	ctx := context.Background()
	userID := setupExpenseAIRateLimitTest(t, ctx)
	if _, err := appState.DB.Pool.Exec(ctx, `
		INSERT INTO expense_ai_search_attempts (user_id, created_at)
		VALUES ($1, now() - interval '49 hours'), ($1, now() - interval '47 hours')
	`, userID); err != nil {
		t.Fatalf("insert retained and expired AI attempts: %v", err)
	}
	if err := pruneAuthHistory(ctx); err != nil {
		t.Fatalf("prune authentication history: %v", err)
	}
	var count int
	if err := appState.DB.Pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM expense_ai_search_attempts WHERE user_id = $1
	`, userID).Scan(&count); err != nil {
		t.Fatalf("count retained AI attempts: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected only the attempt younger than 48 hours to remain, got %d", count)
	}
}

func setupExpenseAIRateLimitTest(t *testing.T, ctx context.Context) string {
	t.Helper()
	db := openSMSAuthTestDB(t)
	previousState := appState
	appState.DB = db
	t.Cleanup(func() { appState = previousState })
	if _, err := db.Pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS expense_ai_search_attempts (
			id BIGSERIAL PRIMARY KEY,
			user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)
	`); err != nil {
		t.Fatalf("create expense AI quota table: %v", err)
	}
	return insertExpenseAIRateLimitTestUser(t, ctx)
}

func insertExpenseAIRateLimitTestUser(t *testing.T, ctx context.Context) string {
	t.Helper()
	phone := fmt.Sprintf("+996%012d", time.Now().UnixNano()%1_000_000_000_000)
	var userID string
	if err := appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO users (phone) VALUES ($1) RETURNING id::text
	`, phone).Scan(&userID); err != nil {
		t.Fatalf("create expense AI test user: %v", err)
	}
	return userID
}
