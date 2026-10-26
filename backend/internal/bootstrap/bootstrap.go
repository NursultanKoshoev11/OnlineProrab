package bootstrap

import (
	"context"
	"log/slog"
	"os"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

func OpenDatabase(ctx context.Context, cfg config.Config) *database.DB {
	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database_open_failed", "error", err)
		os.Exit(1)
	}
	return db
}
