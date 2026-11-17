package httpapi

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

const (
	expenseAISearchWindow       = time.Hour
	maxExpenseAISearchesPerUser = 12
	expenseAISearchRetention    = 48 * time.Hour
)

// reserveExpenseAISearch enforces one quota across all API replicas.
func reserveExpenseAISearch(ctx context.Context, userID string) (int, error) {
	if appState.DB == nil || appState.DB.Pool == nil {
		return 0, errors.New("database is not available")
	}
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return 0, errors.New("user ID is required")
	}

	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		SELECT pg_advisory_xact_lock(hashtextextended($1, 0))
	`, "stroy:expense-ai:user:"+userID); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		DELETE FROM expense_ai_search_attempts
		WHERE user_id = $1
		  AND created_at < statement_timestamp() - make_interval(secs => $2::double precision)
	`, userID, expenseAISearchRetention.Seconds()); err != nil {
		return 0, err
	}

	var attempts int64
	var oldest pgtype.Timestamptz
	var databaseNow time.Time
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*), MIN(created_at), statement_timestamp()
		FROM expense_ai_search_attempts
		WHERE user_id = $1
		  AND created_at > statement_timestamp() - make_interval(secs => $2::double precision)
	`, userID, expenseAISearchWindow.Seconds()).Scan(&attempts, &oldest, &databaseNow); err != nil {
		return 0, err
	}
	if attempts >= maxExpenseAISearchesPerUser {
		if !oldest.Valid {
			return int(expenseAISearchWindow / time.Second), nil
		}
		remaining := oldest.Time.Add(expenseAISearchWindow).Sub(databaseNow)
		retryAfter := int(math.Ceil(remaining.Seconds()))
		if retryAfter < 1 {
			retryAfter = 1
		}
		return retryAfter, nil
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO expense_ai_search_attempts (user_id, created_at)
		VALUES ($1, statement_timestamp())
	`, userID); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return 0, nil
}
