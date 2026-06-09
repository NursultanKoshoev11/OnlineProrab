package bootstrap

import (
    "context"
    "log"

    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

func OpenDatabase(ctx context.Context, cfg config.Config) *database.DB {
    db, err := database.Open(ctx, cfg.DatabaseURL)
    if err != nil {
        log.Fatal(err)
    }
    return db
}
