package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

const (
	DevelopmentEnv = "development"
	ProductionEnv  = "production"
)

const (
	SMSProviderTwilio = "twilio"
)

const (
	minProductionSigningKeyLength = 32
	minProductionAccessTokenTTL   = 5 * time.Minute
	maxProductionAccessTokenTTL   = 60 * time.Minute
)

type Config struct {
	Env                       string
	HTTPAddr                  string
	DatabaseURL               string
	JWTSecret                 string
	AccessTokenTTL            time.Duration
	CORSAllowedOrigins        []string
	UploadDir                 string
	MaxUploadBytes            int64
	SMSProvider               string
	TwilioAccountSID          string
	TwilioAPIKeySID           string
	TwilioAPIKeySecret        string
	TwilioFrom                string
	TwilioMessagingServiceSID string
}

func Load() Config {
	_ = godotenv.Load()

	cfg := Config{}
	cfg.Env = getEnv("APP_ENV", DevelopmentEnv)
	cfg.HTTPAddr = getEnv("HTTP_ADDR", ":8080")
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	cfg.JWTSecret = os.Getenv("JWT_SECRET")
	cfg.AccessTokenTTL = time.Duration(getEnvInt("ACCESS_TOKEN_TTL_MINUTES", 15)) * time.Minute
	cfg.CORSAllowedOrigins = splitCSV(getEnv("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"))
	cfg.UploadDir = getEnv("UPLOAD_DIR", "./uploads")
	cfg.MaxUploadBytes = int64(getEnvInt("MAX_UPLOAD_MB", 10)) * 1024 * 1024
	cfg.SMSProvider = strings.ToLower(strings.TrimSpace(os.Getenv("SMS_PROVIDER")))
	cfg.TwilioAccountSID = strings.TrimSpace(os.Getenv("TWILIO_ACCOUNT_SID"))
	cfg.TwilioAPIKeySID = strings.TrimSpace(os.Getenv("TWILIO_API_KEY_SID"))
	cfg.TwilioAPIKeySecret = strings.TrimSpace(os.Getenv("TWILIO_API_KEY_SECRET"))
	cfg.TwilioFrom = strings.TrimSpace(os.Getenv("TWILIO_FROM"))
	cfg.TwilioMessagingServiceSID = strings.TrimSpace(os.Getenv("TWILIO_MESSAGING_SERVICE_SID"))
	return cfg
}

func (cfg Config) IsProduction() bool {
	return strings.EqualFold(cfg.Env, ProductionEnv)
}

func (cfg Config) Validate() error {
	var problems []string

	if !strings.EqualFold(cfg.Env, DevelopmentEnv) && !strings.EqualFold(cfg.Env, ProductionEnv) {
		problems = append(problems, "APP_ENV must be development or production")
	}
	if strings.TrimSpace(cfg.HTTPAddr) == "" {
		problems = append(problems, "HTTP_ADDR is required")
	}
	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		problems = append(problems, "DATABASE_URL is required")
	}
	if strings.TrimSpace(cfg.UploadDir) == "" {
		problems = append(problems, "UPLOAD_DIR is required")
	}
	if cfg.AccessTokenTTL <= 0 {
		problems = append(problems, "ACCESS_TOKEN_TTL_MINUTES must be greater than 0")
	}
	if cfg.MaxUploadBytes <= 0 {
		problems = append(problems, "MAX_UPLOAD_MB must be greater than 0")
	}
	if cfg.SMSProvider != "" && cfg.SMSProvider != SMSProviderTwilio {
		problems = append(problems, "SMS_PROVIDER must be twilio when configured")
	}
	if cfg.SMSProvider == SMSProviderTwilio {
		problems = append(problems, validateTwilioConfig(cfg)...)
	}
	if cfg.IsProduction() {
		if strings.TrimSpace(cfg.JWTSecret) == "" {
			problems = append(problems, "JWT_SECRET is required in production")
		}
		if isUnsafeSigningKey(cfg.JWTSecret) {
			problems = append(problems, "JWT_SECRET must be replaced before production")
		}
		if cfg.AccessTokenTTL < minProductionAccessTokenTTL || cfg.AccessTokenTTL > maxProductionAccessTokenTTL {
			problems = append(problems, "ACCESS_TOKEN_TTL_MINUTES must be between 5 and 60 in production")
		}
		if len(cfg.CORSAllowedOrigins) == 0 {
			problems = append(problems, "CORS_ALLOWED_ORIGINS is required in production")
		}
		for _, origin := range cfg.CORSAllowedOrigins {
			if isUnsafeProductionOrigin(origin) {
				problems = append(problems, "CORS_ALLOWED_ORIGINS contains a non-production origin")
				break
			}
		}
		if cfg.SMSProvider != SMSProviderTwilio {
			problems = append(problems, "SMS_PROVIDER=twilio is required in production")
		}
	}

	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}
	return nil
}

func validateTwilioConfig(cfg Config) []string {
	var problems []string
	if !strings.HasPrefix(cfg.TwilioAccountSID, "AC") || len(cfg.TwilioAccountSID) < 10 {
		problems = append(problems, "TWILIO_ACCOUNT_SID is required and must be an Account SID")
	}
	if !strings.HasPrefix(cfg.TwilioAPIKeySID, "SK") || len(cfg.TwilioAPIKeySID) < 10 {
		problems = append(problems, "TWILIO_API_KEY_SID is required and must be an API Key SID")
	}
	if len(cfg.TwilioAPIKeySecret) < 16 {
		problems = append(problems, "TWILIO_API_KEY_SECRET is required")
	}
	fromSet := strings.TrimSpace(cfg.TwilioFrom) != ""
	serviceSet := strings.TrimSpace(cfg.TwilioMessagingServiceSID) != ""
	if fromSet == serviceSet {
		problems = append(problems, "configure exactly one of TWILIO_FROM or TWILIO_MESSAGING_SERVICE_SID")
	}
	if serviceSet && (!strings.HasPrefix(cfg.TwilioMessagingServiceSID, "MG") || len(cfg.TwilioMessagingServiceSID) < 10) {
		problems = append(problems, "TWILIO_MESSAGING_SERVICE_SID must be a Messaging Service SID")
	}
	return problems
}

func isUnsafeSigningKey(value string) bool {
	trimmed := strings.TrimSpace(value)
	if len(trimmed) < minProductionSigningKeyLength {
		return true
	}
	lower := strings.ToLower(trimmed)
	return strings.Contains(lower, "change-this") || strings.Contains(lower, "dev-only") || strings.Contains(lower, "secret")
}

func isUnsafeProductionOrigin(origin string) bool {
	value := strings.ToLower(strings.TrimSpace(origin))
	return value == "*" || strings.Contains(value, "localhost") || strings.Contains(value, "127.0.0.1") || strings.Contains(value, "0.0.0.0")
}

func getEnv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func getEnvInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		panic(fmt.Sprintf("invalid integer value for %s: %q", key, value))
	}
	return parsed
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	items := make([]string, 0, len(parts))
	for _, part := range parts {
		item := strings.TrimSpace(part)
		if item != "" {
			items = append(items, item)
		}
	}
	return items
}
