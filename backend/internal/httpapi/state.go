package httpapi

import (
	"context"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

var appState = State{
	JWTSecret:      "dev-only-change-me",
	AccessTokenTTL: 15 * time.Minute,
}

type SMSSender interface {
	SendLoginCode(ctx context.Context, phone, code string) error
}

type State struct {
	DB             *database.DB
	JWTSecret      string
	AccessTokenTTL time.Duration
	UploadDir      string
	MaxUploadBytes int64
	IsProduction   bool
	SMSSender      SMSSender
}

func SetState(cfg config.Config, db *database.DB, smsSender SMSSender) {
	appState = State{
		DB:             db,
		JWTSecret:      cfg.JWTSecret,
		AccessTokenTTL: cfg.AccessTokenTTL,
		UploadDir:      cfg.UploadDir,
		MaxUploadBytes: cfg.MaxUploadBytes,
		IsProduction:   cfg.IsProduction(),
		SMSSender:      smsSender,
	}
	if appState.JWTSecret == "" {
		appState.JWTSecret = "dev-only-change-me"
	}
	if appState.AccessTokenTTL <= 0 {
		appState.AccessTokenTTL = 15 * time.Minute
	}
}
