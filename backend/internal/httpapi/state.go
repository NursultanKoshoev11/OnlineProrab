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
	DB                       *database.DB
	JWTSecret                string
	AccessTokenTTL           time.Duration
	UploadDir                string
	MaxUploadBytes           int64
	IsProduction             bool
	SMSSender                SMSSender
	SupportTelegramBotToken  string
	SupportTelegramChatID    string
	SupportTelegramURL       string
	SupportWhatsAppToken     string
	SupportWhatsAppPhoneID   string
	SupportWhatsAppTo        string
	SupportWhatsAppURL       string
	GeminiAPIKey             string
	GeminiModel              string
	AIProviderOrder          []string
	GroqAPIKey               string
	GroqModel                string
	OpenRouterAPIKey         string
	OpenRouterModel          string
	OpenRouterFallbackModel  string
	PaymentTestMode          bool
	PaymentReturnURL         string
	PaymentWebhookURL        string
	OptimaPaymentURLTemplate string
}

func SetState(cfg config.Config, db *database.DB, smsSender SMSSender) {
	appState = State{
		DB:                       db,
		JWTSecret:                cfg.JWTSecret,
		AccessTokenTTL:           cfg.AccessTokenTTL,
		UploadDir:                cfg.UploadDir,
		MaxUploadBytes:           cfg.MaxUploadBytes,
		IsProduction:             cfg.IsProduction(),
		SMSSender:                smsSender,
		SupportTelegramBotToken:  cfg.SupportTelegramBotToken,
		SupportTelegramChatID:    cfg.SupportTelegramChatID,
		SupportTelegramURL:       cfg.SupportTelegramURL,
		SupportWhatsAppToken:     cfg.SupportWhatsAppToken,
		SupportWhatsAppPhoneID:   cfg.SupportWhatsAppPhoneID,
		SupportWhatsAppTo:        cfg.SupportWhatsAppTo,
		SupportWhatsAppURL:       cfg.SupportWhatsAppURL,
		GeminiAPIKey:             cfg.GeminiAPIKey,
		GeminiModel:              cfg.GeminiModel,
		AIProviderOrder:          cfg.AIProviderOrder,
		GroqAPIKey:               cfg.GroqAPIKey,
		GroqModel:                cfg.GroqModel,
		OpenRouterAPIKey:         cfg.OpenRouterAPIKey,
		OpenRouterModel:          cfg.OpenRouterModel,
		OpenRouterFallbackModel:  cfg.OpenRouterFallbackModel,
		PaymentTestMode:          cfg.PaymentTestMode,
		PaymentReturnURL:         cfg.PaymentReturnURL,
		PaymentWebhookURL:        cfg.PaymentWebhookURL,
		OptimaPaymentURLTemplate: cfg.OptimaPaymentURLTemplate,
	}
	if appState.JWTSecret == "" {
		appState.JWTSecret = "dev-only-change-me"
	}
	if appState.AccessTokenTTL <= 0 {
		appState.AccessTokenTTL = 15 * time.Minute
	}
}
