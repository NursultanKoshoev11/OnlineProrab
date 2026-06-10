package config

import "testing"

func TestValidateRequiresProductionSecrets(t *testing.T) {
	cfg := Config{
		Env:                ProductionEnv,
		HTTPAddr:           ":8080",
		DatabaseURL:        "postgres://user:pass@localhost:5432/app?sslmode=disable",
		JWTSecret:          "change-this-secret-before-production",
		AccessTokenTTL:     1,
		CORSAllowedOrigins: []string{"https://example.com"},
		MaxUploadBytes:     1,
	}

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected production config validation to reject default JWT secret")
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
