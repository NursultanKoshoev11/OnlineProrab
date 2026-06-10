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

type Config struct {
	Env                   string
	HTTPAddr              string
	DatabaseURL           string
	JWTSecret             string
	AccessTokenTTL        time.Duration
	CORSAllowedOrigins    []string
	UploadDir             string
	MaxUploadBytes        int64
}

func Load() Config {
	_ = godotenv.Load()

	cfg := Config{}
	cfg.Env = getEnv("APP_ENV", DevelopmentEnv)
	cfg.HTTPAddr = getEnv("HTTP_ADDR", ":8080")
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	cfg.JWTSecret = os.Getenv("JWT_SECRET")
	cfg.AccessTokenTTL = time.Duration(getEnvInt("ACCESS_TOKEN_TTL_MINUTES", 60)) * time.Minute
	cfg.CORSAllowedOrigins = splitCSV(getEnv("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"))
	cfg.UploadDir = getEnv("UPLOAD_DIR", "./uploads")
	cfg.MaxUploadBytes = int64(getEnvInt("MAX_UPLOAD_MB", 10)) * 1024 * 1024
	return cfg
}

func (cfg Config) IsProduction() bool {
	return strings.EqualFold(cfg.Env, ProductionEnv)
}

func (cfg Config) Validate() error {
	var problems []string

	if strings.TrimSpace(cfg.HTTPAddr) == "" {
		problems = append(problems, "HTTP_ADDR is required")
	}
	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		problems = append(problems, "DATABASE_URL is required")
	}
	if cfg.AccessTokenTTL <= 0 {
		problems = append(problems, "ACCESS_TOKEN_TTL_MINUTES must be greater than 0")
	}
	if cfg.MaxUploadBytes <= 0 {
		problems = append(problems, "MAX_UPLOAD_MB must be greater than 0")
	}
	if cfg.IsProduction() {
		if strings.TrimSpace(cfg.JWTSecret) == "" {
			problems = append(problems, "JWT_SECRET is required in production")
		}
		if cfg.JWTSecret == "change-this-secret-before-production" {
			problems = append(problems, "JWT_SECRET must be changed before production")
		}
		if len(cfg.CORSAllowedOrigins) == 0 {
			problems = append(problems, "CORS_ALLOWED_ORIGINS is required in production")
		}
	}

	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}
	return nil
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
