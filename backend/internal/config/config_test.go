package config

import (
	"strings"
	"testing"
	"time"
)

func TestValidateRequiresProductionSafeSigningKey(t *testing.T) {
	cfg := validProductionConfig()
	cfg.JWTSecret = "change-this-secret-before-production"

	err := cfg.Validate()
	if err == nil {
		t.Fatal("expected production config validation to reject unsafe signing key")
	}
	if !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("expected JWT_SECRET error, got %v", err)
	}
}

func TestValidateRejectsShortProductionSigningKey(t *testing.T) {
	cfg := validProductionConfig()
	cfg.JWTSecret = "short"

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected short production signing key to be rejected")
	}
}

func TestValidateRejectsLocalhostCORSInProduction(t *testing.T) {
	cfg := validProductionConfig()
	cfg.CORSAllowedOrigins = []string{"https://app.example.com", "http://localhost:5173"}

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected localhost CORS origin to be rejected in production")
	}
}

func TestValidateAcceptsSafeProductionConfig(t *testing.T) {
	cfg := validProductionConfig()

	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected valid production config, got %v", err)
	}
}

func TestSplitCSVTrimsEmptyValues(t *testing.T) {
	got := splitCSV(" https://a.example, ,https://b.example ")
	if len(got) != 2 {
		t.Fatalf("expected 2 values, got %d", len(got))
	}
	if got[0] != "https://a.example" || got[1] != "https://b.example" {
		t.Fatalf("unexpected values: %#v", got)
	}
}

func validProductionConfig() Config {
	return Config{
		Env:                ProductionEnv,
		HTTPAddr:           ":8080",
		DatabaseURL:        "postgres://user:pass@db.example.com:5432/app",
		JWTSecret:          "abcdefghijklmnopqrstuvwxyz1234567890",
		AccessTokenTTL:     time.Hour,
		CORSAllowedOrigins: []string{"https://app.example.com"},
		UploadDir:          "/var/lib/onlineprorab/uploads",
		MaxUploadBytes:     10 * 1024 * 1024,
	}
}
