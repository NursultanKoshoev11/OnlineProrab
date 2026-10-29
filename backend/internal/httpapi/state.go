package httpapi

import (
	"context"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

var appState = State{
	JWTSecret:      "dev-only-change-me",
	AccessTokenTTL: 15 * time.Minute,
}

type SMSSender interface {
	SendLoginCode(ctx context.Context, phone, code string) error
}

type State struct {
	DB                           *database.DB
	FileStore                    storage.ObjectStore
	DeletionJournal              storage.DeletionJournal
	JWTSecret                    string
	AccessTokenTTL               time.Duration
	UploadDir                    string
	MaxUploadBytes               int64
	IsProduction                 bool
	IsProductionLike             bool
	IsDevelopment                bool
	TrustedProxyCIDRs            []string
	DevSMSCodeEnabled            bool
	ReviewOnlyMode               bool
	ReviewSMSPhone               string
	ReviewSMSCode                string
	StagingTestSMSPhone          string
	StagingTestSMSCode           string
	StagingTestPaymentPriceKGS   int
	SubscriptionPriceOverrideKGS int
	SMSSender                    SMSSender
	SupportTelegramBotToken      string
	SupportTelegramChatID        string
	SupportTelegramURL           string
	SupportWhatsAppToken         string
	SupportWhatsAppPhoneID       string
	SupportWhatsAppTo            string
	SupportWhatsAppURL           string
	GeminiAPIKey                 string
	GeminiModel                  string
	AIProviderOrder              []string
	DeepSeekAPIKey               string
	DeepSeekModel                string
	GroqAPIKey                   string
	GroqModel                    string
	OpenRouterAPIKey             string
	OpenRouterModel              string
	OpenRouterFallbackModel      string
	IsStaging                    bool
	OBank                        config.OBankConfig
}

func SetState(cfg config.Config, db *database.DB, smsSender SMSSender, fileStore storage.ObjectStore) {
	deletionJournal, _ := fileStore.(storage.DeletionJournal)
	appState = State{
		DB:                           db,
		FileStore:                    fileStore,
		DeletionJournal:              deletionJournal,
		JWTSecret:                    cfg.JWTSecret,
		AccessTokenTTL:               cfg.AccessTokenTTL,
		UploadDir:                    cfg.UploadDir,
		MaxUploadBytes:               cfg.MaxUploadBytes,
		IsProduction:                 cfg.IsProduction(),
		IsProductionLike:             cfg.IsProductionLike(),
		IsDevelopment:                cfg.IsDevelopment(),
		TrustedProxyCIDRs:            append([]string(nil), cfg.TrustedProxyCIDRs...),
		DevSMSCodeEnabled:            cfg.DevSMSCodeEnabled,
		ReviewOnlyMode:               cfg.ReviewOnlyMode,
		ReviewSMSPhone:               cfg.ReviewSMSPhone,
		ReviewSMSCode:                cfg.ReviewSMSCode,
		SMSSender:                    smsSender,
		SupportTelegramBotToken:      cfg.SupportTelegramBotToken,
		SupportTelegramChatID:        cfg.SupportTelegramChatID,
		SupportTelegramURL:           cfg.SupportTelegramURL,
		SupportWhatsAppToken:         cfg.SupportWhatsAppToken,
		SupportWhatsAppPhoneID:       cfg.SupportWhatsAppPhoneID,
		SupportWhatsAppTo:            cfg.SupportWhatsAppTo,
		SupportWhatsAppURL:           cfg.SupportWhatsAppURL,
		GeminiAPIKey:                 cfg.GeminiAPIKey,
		GeminiModel:                  cfg.GeminiModel,
		AIProviderOrder:              cfg.AIProviderOrder,
		DeepSeekAPIKey:               cfg.DeepSeekAPIKey,
		DeepSeekModel:                cfg.DeepSeekModel,
		GroqAPIKey:                   cfg.GroqAPIKey,
		GroqModel:                    cfg.GroqModel,
		OpenRouterAPIKey:             cfg.OpenRouterAPIKey,
		OpenRouterModel:              cfg.OpenRouterModel,
		OpenRouterFallbackModel:      cfg.OpenRouterFallbackModel,
		IsStaging:                    cfg.IsStaging(),
		StagingTestSMSPhone:          cfg.StagingTestSMSPhone,
		StagingTestSMSCode:           cfg.StagingTestSMSCode,
		StagingTestPaymentPriceKGS:   cfg.StagingTestPaymentPriceKGS,
		SubscriptionPriceOverrideKGS: cfg.SubscriptionPriceOverrideKGS,
		OBank:                        cfg.OBank,
	}
	if appState.JWTSecret == "" {
		appState.JWTSecret = "dev-only-change-me"
	}
	if appState.AccessTokenTTL <= 0 {
		appState.AccessTokenTTL = 15 * time.Minute
	}
}
