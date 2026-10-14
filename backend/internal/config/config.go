package config

import (
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

const (
	DevelopmentEnv = "development"
	StagingEnv     = "staging"
	ProductionEnv  = "production"
)

const (
	SMSProviderTwilio = "twilio"
	SMSProviderNikita = "nikita"
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
	DevSMSCodeEnabled         bool
	CORSAllowedOrigins        []string
	TrustedProxyCIDRs         []string
	UploadDir                 string
	MaxUploadBytes            int64
	SMSProvider               string
	ReviewOnlyMode            bool
	ReviewSMSPhone            string
	ReviewSMSCode             string
	TwilioAccountSID          string
	TwilioAPIKeySID           string
	TwilioAPIKeySecret        string
	TwilioFrom                string
	TwilioMessagingServiceSID string
	NikitaAPIURL              string
	NikitaLogin               string
	NikitaPassword            string
	NikitaSender              string
	NikitaTestMode            bool
	SupportTelegramBotToken   string
	SupportTelegramChatID     string
	SupportTelegramURL        string
	SupportWhatsAppToken      string
	SupportWhatsAppPhoneID    string
	SupportWhatsAppTo         string
	SupportWhatsAppURL        string
	GeminiAPIKey              string
	GeminiModel               string
	AIProviderOrder           []string
	GroqAPIKey                string
	GroqModel                 string
	OpenRouterAPIKey          string
	OpenRouterModel           string
	OpenRouterFallbackModel   string
}

func Load() Config {
	processEnv := strings.TrimSpace(os.Getenv("APP_ENV"))
	if shouldLoadDotEnv(processEnv) {
		_ = godotenv.Load()
	}

	cfg := Config{}
	cfg.Env = getEnv("APP_ENV", "")
	cfg.HTTPAddr = getEnv("HTTP_ADDR", ":8080")
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	cfg.JWTSecret = os.Getenv("JWT_SECRET")
	cfg.AccessTokenTTL = time.Duration(getEnvInt("ACCESS_TOKEN_TTL_MINUTES", 15)) * time.Minute
	cfg.DevSMSCodeEnabled = getEnvBool("DEV_SMS_CODE_ENABLED", false)
	cfg.CORSAllowedOrigins = splitCSV(getEnv("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"))
	cfg.TrustedProxyCIDRs = splitCSV(os.Getenv("TRUSTED_PROXY_CIDRS"))
	cfg.UploadDir = getEnv("UPLOAD_DIR", "./uploads")
	cfg.MaxUploadBytes = int64(getEnvInt("MAX_UPLOAD_MB", 10)) * 1024 * 1024
	cfg.SMSProvider = strings.ToLower(strings.TrimSpace(os.Getenv("SMS_PROVIDER")))
	cfg.ReviewOnlyMode = getEnvBool("REVIEW_ONLY_MODE", false)
	cfg.ReviewSMSPhone = normalizePhone(os.Getenv("REVIEW_SMS_PHONE"))
	cfg.ReviewSMSCode = strings.TrimSpace(os.Getenv("REVIEW_SMS_CODE"))
	cfg.TwilioAccountSID = strings.TrimSpace(os.Getenv("TWILIO_ACCOUNT_SID"))
	cfg.TwilioAPIKeySID = strings.TrimSpace(os.Getenv("TWILIO_API_KEY_SID"))
	cfg.TwilioAPIKeySecret = strings.TrimSpace(os.Getenv("TWILIO_API_KEY_SECRET"))
	cfg.TwilioFrom = strings.TrimSpace(os.Getenv("TWILIO_FROM"))
	cfg.TwilioMessagingServiceSID = strings.TrimSpace(os.Getenv("TWILIO_MESSAGING_SERVICE_SID"))
	cfg.NikitaAPIURL = getEnv("NIKITA_API_URL", "https://smspro.nikita.kg/api/message")
	cfg.NikitaLogin = strings.TrimSpace(os.Getenv("NIKITA_LOGIN"))
	cfg.NikitaPassword = strings.TrimSpace(os.Getenv("NIKITA_PASSWORD"))
	cfg.NikitaSender = strings.TrimSpace(os.Getenv("NIKITA_SENDER"))
	cfg.NikitaTestMode = getEnvBool("NIKITA_TEST_MODE", false)
	cfg.SupportTelegramBotToken = strings.TrimSpace(os.Getenv("SUPPORT_TELEGRAM_BOT_TOKEN"))
	cfg.SupportTelegramChatID = strings.TrimSpace(os.Getenv("SUPPORT_TELEGRAM_CHAT_ID"))
	cfg.SupportTelegramURL = strings.TrimSpace(os.Getenv("SUPPORT_TELEGRAM_URL"))
	cfg.SupportWhatsAppToken = strings.TrimSpace(os.Getenv("SUPPORT_WHATSAPP_ACCESS_TOKEN"))
	cfg.SupportWhatsAppPhoneID = strings.TrimSpace(os.Getenv("SUPPORT_WHATSAPP_PHONE_NUMBER_ID"))
	cfg.SupportWhatsAppTo = strings.TrimSpace(os.Getenv("SUPPORT_WHATSAPP_TO"))
	cfg.SupportWhatsAppURL = strings.TrimSpace(os.Getenv("SUPPORT_WHATSAPP_URL"))
	cfg.GeminiAPIKey = strings.TrimSpace(os.Getenv("GEMINI_API_KEY"))
	cfg.GeminiModel = getEnv("GEMINI_MODEL", "gemini-3.5-flash-lite")
	cfg.AIProviderOrder = splitCSV(getEnv("AI_PROVIDER_ORDER", "gemini,groq,openrouter,openrouter-fallback"))
	cfg.GroqAPIKey = strings.TrimSpace(os.Getenv("GROQ_API_KEY"))
	cfg.GroqModel = getEnv("GROQ_MODEL", "openai/gpt-oss-20b")
	cfg.OpenRouterAPIKey = strings.TrimSpace(os.Getenv("OPENROUTER_API_KEY"))
	cfg.OpenRouterModel = getEnv("OPENROUTER_MODEL", "openrouter/free")
	cfg.OpenRouterFallbackModel = getEnv("OPENROUTER_FALLBACK_MODEL", "nex-agi/nex-n2.5-pro:free")
	return cfg
}

func shouldLoadDotEnv(processEnv string) bool {
	if processEnv != "" {
		return strings.EqualFold(processEnv, DevelopmentEnv)
	}

	dotEnv, err := godotenv.Read()
	return err == nil && strings.EqualFold(strings.TrimSpace(dotEnv["APP_ENV"]), DevelopmentEnv)
}

func (cfg Config) IsProduction() bool {
	return strings.EqualFold(cfg.Env, ProductionEnv)
}

func (cfg Config) IsDevelopment() bool {
	return strings.EqualFold(cfg.Env, DevelopmentEnv)
}

func (cfg Config) IsStaging() bool {
	return strings.EqualFold(cfg.Env, StagingEnv)
}

func (cfg Config) IsProductionLike() bool {
	return cfg.IsProduction() || cfg.IsStaging()
}

func (cfg Config) Validate() error {
	var problems []string

	if !cfg.IsDevelopment() && !cfg.IsStaging() && !cfg.IsProduction() {
		problems = append(problems, "APP_ENV must be explicitly set to development, staging, or production")
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
	if cfg.SMSProvider != "" && cfg.SMSProvider != SMSProviderTwilio && cfg.SMSProvider != SMSProviderNikita {
		problems = append(problems, "SMS_PROVIDER must be twilio or nikita when configured")
	}
	if cfg.SMSProvider == SMSProviderTwilio {
		problems = append(problems, validateTwilioConfig(cfg)...)
	}
	if cfg.SMSProvider == SMSProviderNikita {
		problems = append(problems, validateNikitaConfig(cfg)...)
	}
	if cfg.DevSMSCodeEnabled && !cfg.IsDevelopment() {
		problems = append(problems, "DEV_SMS_CODE_ENABLED is allowed only when APP_ENV=development")
	}
	if cfg.DevSMSCodeEnabled && !isLoopbackHTTPAddr(cfg.HTTPAddr) {
		problems = append(problems, "DEV_SMS_CODE_ENABLED requires HTTP_ADDR to use a loopback address")
	}
	if cfg.NikitaTestMode && !cfg.IsDevelopment() {
		problems = append(problems, "NIKITA_TEST_MODE is allowed only when APP_ENV=development")
	}
	if cfg.NikitaTestMode && !isLoopbackHTTPAddr(cfg.HTTPAddr) {
		problems = append(problems, "NIKITA_TEST_MODE requires HTTP_ADDR to use a loopback address")
	}

	reviewPhoneSet := cfg.ReviewSMSPhone != ""
	reviewCodeSet := cfg.ReviewSMSCode != ""
	if reviewPhoneSet != reviewCodeSet {
		problems = append(problems, "REVIEW_SMS_PHONE and REVIEW_SMS_CODE must be configured together")
	}
	if (reviewPhoneSet || reviewCodeSet) && !cfg.ReviewOnlyMode {
		problems = append(problems, "REVIEW_ONLY_MODE=true is required when review credentials are configured")
	}
	if reviewPhoneSet && !isValidPhone(cfg.ReviewSMSPhone) {
		problems = append(problems, "REVIEW_SMS_PHONE must be a valid E.164 phone number")
	}
	if reviewCodeSet && !isSixDigitCode(cfg.ReviewSMSCode) {
		problems = append(problems, "REVIEW_SMS_CODE must be exactly 6 digits")
	}

	if cfg.ReviewOnlyMode && !cfg.IsProduction() {
		problems = append(problems, "REVIEW_ONLY_MODE is allowed only when APP_ENV=production")
	}

	if cfg.IsProductionLike() {
		if cfg.IsStaging() && cfg.ReviewOnlyMode {
			problems = append(problems, "REVIEW_ONLY_MODE is not allowed in staging")
		}
		if strings.TrimSpace(cfg.JWTSecret) == "" {
			problems = append(problems, "JWT_SECRET is required in staging and production")
		}
		if isUnsafeSigningKey(cfg.JWTSecret) {
			problems = append(problems, "JWT_SECRET must be replaced before staging or production")
		}
		if cfg.AccessTokenTTL < minProductionAccessTokenTTL || cfg.AccessTokenTTL > maxProductionAccessTokenTTL {
			problems = append(problems, "ACCESS_TOKEN_TTL_MINUTES must be between 5 and 60 in staging and production")
		}
		if len(cfg.CORSAllowedOrigins) == 0 {
			problems = append(problems, "CORS_ALLOWED_ORIGINS is required in staging and production")
		}
		for _, origin := range cfg.CORSAllowedOrigins {
			if isUnsafeProductionOrigin(origin) {
				problems = append(problems, "CORS_ALLOWED_ORIGINS contains an insecure origin")
				break
			}
		}
		if len(cfg.TrustedProxyCIDRs) == 0 {
			problems = append(problems, "TRUSTED_PROXY_CIDRS must identify the reverse proxies that reach the API")
		} else {
			for _, value := range cfg.TrustedProxyCIDRs {
				prefix, err := parseTrustedProxyCIDR(value)
				if err != nil || prefix.Bits() == 0 || prefix.Addr().IsUnspecified() {
					problems = append(problems, "TRUSTED_PROXY_CIDRS must contain explicit proxy IP addresses or CIDRs, not an unrestricted range")
					break
				}
			}
		}
		if cfg.IsStaging() && cfg.SMSProvider != SMSProviderTwilio && cfg.SMSProvider != SMSProviderNikita {
			problems = append(problems, "SMS_PROVIDER=twilio or nikita is required in staging")
		}
		if cfg.IsProduction() && !cfg.ReviewOnlyMode && cfg.SMSProvider != SMSProviderTwilio && cfg.SMSProvider != SMSProviderNikita {
			problems = append(problems, "SMS_PROVIDER=twilio or nikita is required in production unless REVIEW_ONLY_MODE is enabled")
		}
		if cfg.IsStaging() {
			if err := validateVerifiedDatabaseTLS(cfg.DatabaseURL); err != nil {
				problems = append(problems, err.Error())
			}
		}
	}

	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}
	return nil
}

func parseTrustedProxyCIDR(value string) (netip.Prefix, error) {
	value = strings.TrimSpace(value)
	if addr, err := netip.ParseAddr(value); err == nil {
		addr = addr.Unmap()
		return netip.PrefixFrom(addr, addr.BitLen()), nil
	}
	prefix, err := netip.ParsePrefix(value)
	if err != nil || prefix.Addr().Is4In6() {
		return netip.Prefix{}, errors.New("invalid trusted proxy address or CIDR")
	}
	return prefix.Masked(), nil
}

func validateVerifiedDatabaseTLS(databaseURL string) error {
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return errors.New("DATABASE_URL must be a valid PostgreSQL URL with verified TLS in staging")
	}
	if !usesVerifiedPostgresTLS(poolConfig.ConnConfig.TLSConfig) {
		return errors.New("DATABASE_URL must use sslmode=verify-full in staging")
	}
	for _, fallback := range poolConfig.ConnConfig.Fallbacks {
		if !usesVerifiedPostgresTLS(fallback.TLSConfig) {
			return errors.New("DATABASE_URL must use sslmode=verify-full for every staging database host")
		}
	}
	return nil
}

func usesVerifiedPostgresTLS(tlsConfig *tls.Config) bool {
	return tlsConfig != nil && !tlsConfig.InsecureSkipVerify && strings.TrimSpace(tlsConfig.ServerName) != ""
}

func isLoopbackHTTPAddr(addr string) bool {
	host, _, err := net.SplitHostPort(strings.TrimSpace(addr))
	if err != nil {
		return false
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
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

func validateNikitaConfig(cfg Config) []string {
	var problems []string
	if strings.TrimSpace(cfg.NikitaAPIURL) == "" {
		problems = append(problems, "NIKITA_API_URL is required")
	}
	if strings.TrimSpace(cfg.NikitaLogin) == "" {
		problems = append(problems, "NIKITA_LOGIN is required")
	}
	if strings.TrimSpace(cfg.NikitaPassword) == "" {
		problems = append(problems, "NIKITA_PASSWORD is required")
	}
	if strings.TrimSpace(cfg.NikitaSender) == "" {
		problems = append(problems, "NIKITA_SENDER is required")
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
	parsed, err := url.Parse(strings.TrimSpace(origin))
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return true
	}
	if parsed.User != nil || parsed.Opaque != "" || parsed.Path != "" || parsed.RawQuery != "" || parsed.ForceQuery || parsed.Fragment != "" {
		return true
	}
	if strings.Contains(parsed.Host, "*") {
		return true
	}

	host := strings.TrimSuffix(strings.ToLower(parsed.Hostname()), ".")
	if host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return true
	}
	if ip := net.ParseIP(host); ip != nil && (ip.IsLoopback() || ip.IsUnspecified()) {
		return true
	}
	return false
}

func normalizePhone(value string) string {
	return strings.ReplaceAll(strings.TrimSpace(value), " ", "")
}

func isValidPhone(value string) bool {
	value = normalizePhone(value)
	if strings.HasPrefix(value, "+") {
		value = value[1:]
	}
	if len(value) < 9 || len(value) > 15 {
		return false
	}
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}

func isSixDigitCode(value string) bool {
	if len(value) != 6 {
		return false
	}
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}

func getEnvBool(key string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		panic(fmt.Sprintf("invalid boolean value for %s: %q", key, value))
	}
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
