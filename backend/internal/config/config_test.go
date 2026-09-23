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

func TestValidateRejectsUnknownEnvironment(t *testing.T) {
	cfg := validProductionConfig()
	cfg.Env = "prod"

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected unknown APP_ENV to be rejected")
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

func TestValidateRejectsTooShortProductionAccessTokenTTL(t *testing.T) {
	cfg := validProductionConfig()
	cfg.AccessTokenTTL = 4 * time.Minute

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected short production access token TTL to be rejected")
	}
}

func TestValidateRejectsTooLongProductionAccessTokenTTL(t *testing.T) {
	cfg := validProductionConfig()
	cfg.AccessTokenTTL = 61 * time.Minute

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected long production access token TTL to be rejected")
	}
}

func TestValidateRequiresSMSProviderInProduction(t *testing.T) {
	cfg := validProductionConfig()
	cfg.SMSProvider = ""
	cfg.TwilioAccountSID = ""
	cfg.TwilioAPIKeySID = ""
	cfg.TwilioAPIKeySecret = ""
	cfg.TwilioFrom = ""

	err := cfg.Validate()
	if err == nil {
		t.Fatal("expected missing production SMS provider to be rejected")
	}
	if !strings.Contains(err.Error(), "SMS_PROVIDER") {
		t.Fatalf("expected SMS_PROVIDER error, got %v", err)
	}
}

func TestValidateRejectsIncompleteTwilioConfig(t *testing.T) {
	cfg := validProductionConfig()
	cfg.TwilioAPIKeySID = ""

	err := cfg.Validate()
	if err == nil {
		t.Fatal("expected incomplete Twilio config to be rejected")
	}
	if !strings.Contains(err.Error(), "TWILIO_API_KEY_SID") {
		t.Fatalf("expected TWILIO_API_KEY_SID error, got %v", err)
	}
}

func TestValidateRejectsTwoTwilioSenderSources(t *testing.T) {
	cfg := validProductionConfig()
	cfg.TwilioMessagingServiceSID = "MG0000000000"

	err := cfg.Validate()
	if err == nil {
		t.Fatal("expected two Twilio sender sources to be rejected")
	}
	if !strings.Contains(err.Error(), "exactly one") {
		t.Fatalf("expected sender configuration error, got %v", err)
	}
}

func TestValidateAcceptsSafeProductionConfig(t *testing.T) {
	cfg := validProductionConfig()

	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected valid production config, got %v", err)
	}
}

func TestValidateAcceptsNikitaProductionConfig(t *testing.T) {
	cfg := validProductionConfig()
	cfg.SMSProvider = SMSProviderNikita
	cfg.TwilioAccountSID = ""
	cfg.TwilioAPIKeySID = ""
	cfg.TwilioAPIKeySecret = ""
	cfg.TwilioFrom = ""
	cfg.NikitaAPIURL = "https://smspro.nikita.kg/api/message"
	cfg.NikitaLogin = "test-login"
	cfg.NikitaPassword = "test-password"
	cfg.NikitaSender = "SMSPRO.KG"

	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected valid Nikita production config, got %v", err)
	}
}

func TestValidateRejectsIncompleteNikitaConfig(t *testing.T) {
	cfg := validProductionConfig()
	cfg.SMSProvider = SMSProviderNikita
	cfg.TwilioAccountSID = ""
	cfg.TwilioAPIKeySID = ""
	cfg.TwilioAPIKeySecret = ""
	cfg.TwilioFrom = ""
	cfg.NikitaLogin = ""

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected incomplete Nikita config to be rejected")
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
		AccessTokenTTL:     15 * time.Minute,
		CORSAllowedOrigins: []string{"https://app.example.com"},
		UploadDir:          "/var/lib/onlineprorab/uploads",
		MaxUploadBytes:     10 * 1024 * 1024,
		SMSProvider:        SMSProviderTwilio,
		TwilioAccountSID:   "AC0000000000",
		TwilioAPIKeySID:    "SK0000000000",
		TwilioAPIKeySecret: "unit-test-credential-value",
		TwilioFrom:         "+15550000000",
	}
}

func TestValidateAllowsProductionReviewOnlyWithoutSMSProvider(t *testing.T) {
	cfg := validProductionConfig()
	cfg.SMSProvider = ""
	cfg.TwilioAccountSID = ""
	cfg.TwilioAPIKeySID = ""
	cfg.TwilioAPIKeySecret = ""
	cfg.TwilioFrom = ""
	cfg.ReviewOnlyMode = true
	cfg.ReviewSMSPhone = "+996700000001"
	cfg.ReviewSMSCode = "111111"

	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected review-only production config to be valid, got %v", err)
	}
}

func TestValidateRejectsReviewCredentialsWithoutReviewOnlyMode(t *testing.T) {
	cfg := validProductionConfig()
	cfg.ReviewSMSPhone = "+996700000001"
	cfg.ReviewSMSCode = "111111"

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected review credentials without review-only mode to be rejected")
	}
}

func TestValidateRejectsInvalidReviewCode(t *testing.T) {
	cfg := validProductionConfig()
	cfg.ReviewOnlyMode = true
	cfg.ReviewSMSPhone = "+996700000001"
	cfg.ReviewSMSCode = "11111"

	if err := cfg.Validate(); err == nil {
		t.Fatal("expected invalid review code to be rejected")
	}
}
