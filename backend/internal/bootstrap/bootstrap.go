package bootstrap

import (
	"context"
	"log/slog"
	"os"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

// After a host reboot the API container can start before PostgreSQL accepts
// connections. Waiting briefly avoids a crash-and-restart cycle (and a
// spurious error in the logs) while still failing fast on a real outage.
const (
	databaseOpenAttempts   = 30
	databaseOpenRetryDelay = 2 * time.Second
)

func OpenDatabase(ctx context.Context, cfg config.Config) *database.DB {
	db, err := openWithRetry(ctx, databaseOpenAttempts, databaseOpenRetryDelay, func(ctx context.Context) (*database.DB, error) {
		return database.Open(ctx, cfg.DatabaseURL)
	})
	if err != nil {
		slog.Error("database_open_failed", "error", err)
		os.Exit(1)
	}
	return db
}

func openWithRetry(ctx context.Context, attempts int, delay time.Duration, open func(context.Context) (*database.DB, error)) (*database.DB, error) {
	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {
		db, err := open(ctx)
		if err == nil {
			return db, nil
		}
		lastErr = err
		if attempt == attempts {
			break
		}
		slog.Warn("database_not_ready", "attempt", attempt, "error", err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(delay):
		}
	}
	return nil, lastErr
}
