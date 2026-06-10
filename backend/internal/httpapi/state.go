package httpapi

import (
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

var appState = State{
	JWTSecret:      "dev-only-change-me",
	AccessTokenTTL: time.Hour,
}

type State struct {
	DB             *database.DB
	JWTSecret      string
	AccessTokenTTL time.Duration
	UploadDir      string
	MaxUploadBytes int64
}

func SetState(cfg config.Config, db *database.DB) {
	appState = State{
		DB:             db,
		JWTSecret:      cfg.JWTSecret,
		AccessTokenTTL: cfg.AccessTokenTTL,
		UploadDir:      cfg.UploadDir,
		MaxUploadBytes: cfg.MaxUploadBytes,
	}
	if appState.JWTSecret == "" {
		appState.JWTSecret = "dev-only-change-me"
	}
	if appState.AccessTokenTTL <= 0 {
		appState.AccessTokenTTL = time.Hour
	}
}
