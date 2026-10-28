package config

import (
	"crypto/tls"
	"errors"
	"fmt"
	"math"
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
	minProductionSigningKeyLength      = 32
	minProductionSigningKeyEntropyBits = 128.0
	minProductionAccessTokenTTL        = 5 * time.Minute
	maxProductionAccessTokenTTL        = 60 * time.Minute
)

type Config struct {
	Env                        string
	HTTPAddr                   string
	DatabaseURL                string
	JWTSecret                  string
	AccessTokenTTL             time.Duration
	DevSMSCodeEnabled          bool
	CORSAllowedOrigins         []string
	StorageDriver              string
	TrustedProxyCIDRs          []string
	UploadDir                  string
	MaxUploadBytes             int64
	S3Region                   string
	S3Bucket                   string
	S3DeletionLedgerBucket     string
	AWSAccessKeyID             string
	AWSSecretAccessKey         string
	AWSSessionToken            string
	SMSProvider                string
	StagingTestSMSPhone        string
	StagingTestSMSCode         string
	StagingTestPaymentPriceKGS int
	// SubscriptionPriceOverrideKGS is a temporary operator-controlled price
	// override for paid plans. Zero keeps the catalog prices.
	SubscriptionPriceOverrideKGS int
	ReviewOnlyMode               bool
	ReviewSMSPhone               string
	ReviewSMSCode                string
	TwilioAccountSID             string
	TwilioAPIKeySID              string
	TwilioAPIKeySecret           string
	TwilioFrom                   string
	TwilioMessagingServiceSID    string
	NikitaAPIURL                 string
	NikitaLogin                  string
	NikitaPassword               string
	NikitaSender                 string
	NikitaTestMode               bool
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
	GroqAPIKey                   string
	GroqModel                    string
	OpenRouterAPIKey             string
	OpenRouterModel              string
	OpenRouterFallbackModel      string
	OBank                        OBankConfig
}

// OBankConfig contains O!Dengi merchant credentials and fixed return URLs.
// The API password must only be configured on the server.
type OBankConfig struct {
	Enabled       bool
	SID           string
	Password      string
	APIURL        string
	APIVersion    int
	Test          bool
	TestOnlyPhone string
	TestPriceKGS  int
	ResultURL     string
	ReturnURL     string
}

func Load() (Config, error) {
	processEnv := strings.TrimSpace(os.Getenv("APP_ENV"))
	if shouldLoadDotEnv(processEnv) {
		if err := godotenv.Load(); err != nil && !errors.Is(err, os.ErrNotExist) {
			return Config{}, errors.New("failed to load development .env")
		}
	}

	accessTokenTTL, err := getDurationMinutes("ACCESS_TOKEN_TTL_MINUTES", 15)
	if err != nil {
		return Config{}, err
	}
	devSMSCodeEnabled, err := getEnvBool("DEV_SMS_CODE_ENABLED", false)
	if err != nil {
		return Config{}, err
	}
	maxUploadBytes, err := getMegabytes("MAX_UPLOAD_MB", 10)
	if err != nil {
		return Config{}, err
	}
	stagingTestPaymentPriceKGS, err := getEnvInt("STAGING_TEST_PAYMENT_PRICE_KGS", 0)
	if err != nil {
		return Config{}, err
	}
	subscriptionPriceOverrideKGS, err := getEnvInt("SUBSCRIPTION_PRICE_OVERRIDE_KGS", 0)
	if err != nil {
		return Config{}, err
	}
	obankTestPriceKGS, err := getEnvInt("OBANK_TEST_PRICE_KGS", 0)
	if err != nil {
		return Config{}, err
	}
	reviewOnlyMode, err := getEnvBool("REVIEW_ONLY_MODE", false)
	if err != nil {
		return Config{}, err
	}
	nikitaTestMode, err := getEnvBool("NIKITA_TEST_MODE", false)
	if err != nil {
		return Config{}, err
	}
	obankEnabled, err := getEnvBool("OBANK_ENABLED", false)
	if err != nil {
		return Config{}, err
	}
	envName := getEnv("APP_ENV", "")
	obankTest, err := getEnvBool("OBANK_TEST", !strings.EqualFold(envName, ProductionEnv))
	if err != nil {
		return Config{}, err
	}
	obankVersion, err := strconv.Atoi(getEnv("OBANK_API_VERSION", "1005"))
	if err != nil {
		return Config{}, errors.New("OBANK_API_VERSION must be an integer")
	}
	obankAPIURL := strings.TrimSpace(os.Getenv("OBANK_API_URL"))
	if obankAPIURL == "" && !strings.EqualFold(envName, ProductionEnv) {
		obankAPIURL = "https://mw-api-test.dengi.kg/api/json/json.php"
	}

	cfg := Config{}
	cfg.Env = getEnv("APP_ENV", "")
	cfg.HTTPAddr = getEnv("HTTP_ADDR", ":8080")
	cfg.DatabaseURL = os.Getenv("DATABASE_URL")
	cfg.JWTSecret = os.Getenv("JWT_SECRET")
	cfg.AccessTokenTTL = accessTokenTTL
	cfg.DevSMSCodeEnabled = devSMSCodeEnabled
	cfg.CORSAllowedOrigins = splitCSV(getEnv("CORS_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173"))
	cfg.StorageDriver = strings.ToLower(getEnv("STORAGE_DRIVER", "local"))
	cfg.TrustedProxyCIDRs = splitCSV(os.Getenv("TRUSTED_PROXY_CIDRS"))
	cfg.UploadDir = getEnv("UPLOAD_DIR", "./uploads")
	cfg.MaxUploadBytes = maxUploadBytes
	cfg.S3Region = strings.TrimSpace(os.Getenv("S3_REGION"))
	cfg.S3Bucket = strings.TrimSpace(os.Getenv("S3_BUCKET"))
	cfg.S3DeletionLedgerBucket = strings.TrimSpace(os.Getenv("S3_DELETION_LEDGER_BUCKET"))
	cfg.AWSAccessKeyID = strings.TrimSpace(os.Getenv("AWS_ACCESS_KEY_ID"))
	cfg.AWSSecretAccessKey = strings.TrimSpace(os.Getenv("AWS_SECRET_ACCESS_KEY"))
	cfg.AWSSessionToken = strings.TrimSpace(os.Getenv("AWS_SESSION_TOKEN"))
	cfg.SMSProvider = strings.ToLower(strings.TrimSpace(os.Getenv("SMS_PROVIDER")))
	cfg.StagingTestSMSPhone = normalizePhone(os.Getenv("STAGING_TEST_SMS_PHONE"))
	cfg.StagingTestSMSCode = strings.TrimSpace(os.Getenv("STAGING_TEST_SMS_CODE"))
	cfg.StagingTestPaymentPriceKGS = stagingTestPaymentPriceKGS
	cfg.SubscriptionPriceOverrideKGS = subscriptionPriceOverrideKGS
	cfg.ReviewOnlyMode = reviewOnlyMode
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
	cfg.NikitaTestMode = nikitaTestMode
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
	cfg.OBank = OBankConfig{
		Enabled:       obankEnabled,
		SID:           strings.TrimSpace(os.Getenv("OBANK_SID")),
		Password:      strings.TrimSpace(os.Getenv("OBANK_PASSWORD")),
		APIURL:        obankAPIURL,
		APIVersion:    obankVersion,
		Test:          obankTest,
		TestOnlyPhone: normalizePhone(os.Getenv("OBANK_TEST_ONLY_PHONE")),
		TestPriceKGS:  obankTestPriceKGS,
		ResultURL:     strings.TrimSpace(os.Getenv("OBANK_RESULT_URL")),
		ReturnURL:     strings.TrimSpace(os.Getenv("OBANK_RETURN_URL")),
	}
	return cfg, nil
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
	if cfg.StorageDriver != "local" && cfg.StorageDriver != "s3" {
		problems = append(problems, "STORAGE_DRIVER must be local or s3")
	}
	if cfg.IsProductionLike() && cfg.StorageDriver != "s3" {
		problems = append(problems, "STORAGE_DRIVER=s3 is required in staging and production")
	}
	if cfg.StorageDriver == "s3" {
		if cfg.S3Region == "" {
			problems = append(problems, "S3_REGION is required when STORAGE_DRIVER=s3")
		}
		if cfg.S3Bucket == "" {
			problems = append(problems, "S3_BUCKET is required when STORAGE_DRIVER=s3")
		}
		if cfg.S3DeletionLedgerBucket == "" {
			problems = append(problems, "S3_DELETION_LEDGER_BUCKET is required when STORAGE_DRIVER=s3")
		}
		if cfg.S3Bucket != "" && cfg.S3Bucket == cfg.S3DeletionLedgerBucket {
			problems = append(problems, "S3_BUCKET and S3_DELETION_LEDGER_BUCKET must be different")
		}
		if (cfg.AWSAccessKeyID == "") != (cfg.AWSSecretAccessKey == "") {
			problems = append(problems, "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be configured together")
		}
		if cfg.AWSSessionToken != "" && cfg.AWSAccessKeyID == "" {
			problems = append(problems, "AWS_SESSION_TOKEN requires AWS access key credentials")
		}
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
	problems = append(problems, validateOBankConfig(cfg)...)

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

	stagingTestPhoneSet := cfg.StagingTestSMSPhone != ""
	stagingTestCodeSet := cfg.StagingTestSMSCode != ""
	if stagingTestPhoneSet != stagingTestCodeSet {
		problems = append(problems, "STAGING_TEST_SMS_PHONE and STAGING_TEST_SMS_CODE must be configured together")
	}
	if (stagingTestPhoneSet || stagingTestCodeSet) && !cfg.IsStaging() {
		problems = append(problems, "STAGING_TEST_SMS_PHONE and STAGING_TEST_SMS_CODE are allowed only when APP_ENV=staging")
	}
	if stagingTestPhoneSet && !isValidPhone(cfg.StagingTestSMSPhone) {
		problems = append(problems, "STAGING_TEST_SMS_PHONE must be a valid E.164 phone number")
	}
	if stagingTestCodeSet && !isSixDigitCode(cfg.StagingTestSMSCode) {
		problems = append(problems, "STAGING_TEST_SMS_CODE must be exactly 6 digits")
	}
	if cfg.StagingTestPaymentPriceKGS < 0 || cfg.StagingTestPaymentPriceKGS > 100 {
		problems = append(problems, "STAGING_TEST_PAYMENT_PRICE_KGS must be 0 or between 1 and 100")
	}
	if cfg.StagingTestPaymentPriceKGS > 0 && !cfg.IsStaging() {
		problems = append(problems, "STAGING_TEST_PAYMENT_PRICE_KGS is allowed only when APP_ENV=staging")
	}
	if cfg.StagingTestPaymentPriceKGS > 0 && (!cfg.OBank.Enabled || !cfg.OBank.Test) {
		problems = append(problems, "STAGING_TEST_PAYMENT_PRICE_KGS requires OBANK_ENABLED=true and OBANK_TEST=true")
	}
	if cfg.SubscriptionPriceOverrideKGS < 0 || cfg.SubscriptionPriceOverrideKGS > 100 {
		problems = append(problems, "SUBSCRIPTION_PRICE_OVERRIDE_KGS must be 0 or between 1 and 100")
	}
	if cfg.SubscriptionPriceOverrideKGS > 0 && (!cfg.IsProductionLike() || !cfg.OBank.Enabled) {
		problems = append(problems, "SUBSCRIPTION_PRICE_OVERRIDE_KGS requires staging or production with OBANK_ENABLED=true")
	}
	if cfg.OBank.TestPriceKGS < 0 || cfg.OBank.TestPriceKGS > 100 {
		problems = append(problems, "OBANK_TEST_PRICE_KGS must be 0 or between 1 and 100")
	}
	if cfg.IsProduction() && cfg.OBank.Test {
		if !cfg.OBank.Enabled {
			problems = append(problems, "OBANK_ENABLED=true is required for a production sandbox checkout")
		}
		if !isValidPhone(cfg.OBank.TestOnlyPhone) {
			problems = append(problems, "OBANK_TEST_ONLY_PHONE must be a valid E.164 phone number in production sandbox mode")
		}
		if cfg.OBank.TestPriceKGS < 1 || cfg.OBank.TestPriceKGS > 100 {
			problems = append(problems, "OBANK_TEST_PRICE_KGS must be between 1 and 100 in production sandbox mode")
		}
		if !isOBankSandboxURL(cfg.OBank.APIURL) {
			problems = append(problems, "OBANK_API_URL must point to the O!Dengi sandbox in production sandbox mode")
		}
	} else if cfg.OBank.TestOnlyPhone != "" || cfg.OBank.TestPriceKGS != 0 {
		problems = append(problems, "OBANK_TEST_ONLY_PHONE and OBANK_TEST_PRICE_KGS are allowed only in production sandbox mode")
	}

	if cfg.IsProductionLike() {
		if cfg.IsStaging() && cfg.ReviewOnlyMode {
			problems = append(problems, "REVIEW_ONLY_MODE is not allowed in staging")
		}
		if strings.TrimSpace(cfg.JWTSecret) == "" {
			problems = append(problems, "JWT_SECRET is required in staging and production")
		}
		if isUnsafeSigningKey(cfg.JWTSecret) {
			problems = append(problems, "JWT_SECRET must be a high-entropy random value in staging and production")
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
				if err != nil || !isNarrowTrustedProxyPrefix(prefix) {
					problems = append(problems, "TRUSTED_PROXY_CIDRS must use IPv4 prefixes of /16 or longer and IPv6 prefixes of /64 or longer")
					break
				}
			}
		}
		if cfg.IsStaging() && cfg.SMSProvider != SMSProviderTwilio && cfg.SMSProvider != SMSProviderNikita && !(stagingTestPhoneSet && stagingTestCodeSet) {
			problems = append(problems, "SMS_PROVIDER=twilio or nikita is required in staging")
		}
		if cfg.IsProduction() && !cfg.ReviewOnlyMode && cfg.SMSProvider != SMSProviderTwilio && cfg.SMSProvider != SMSProviderNikita {
			problems = append(problems, "SMS_PROVIDER=twilio or nikita is required in production unless REVIEW_ONLY_MODE is enabled")
		}
		if err := validateVerifiedDatabaseTLS(cfg.DatabaseURL); err != nil {
			problems = append(problems, err.Error())
		}
	}

	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}
	return nil
}

func validateOBankConfig(cfg Config) []string {
	if !cfg.OBank.Enabled {
		return nil
	}

	var problems []string
	if cfg.OBank.SID == "" || cfg.OBank.Password == "" {
		problems = append(problems, "OBANK_SID and OBANK_PASSWORD are required when OBANK_ENABLED=true")
	}
	if cfg.OBank.APIVersion <= 0 {
		problems = append(problems, "OBANK_API_VERSION must be greater than 0")
	}
	if cfg.OBank.APIURL == "" || validateOBankURL(cfg.OBank.APIURL, cfg.IsDevelopment()) != nil {
		problems = append(problems, "OBANK_API_URL must be a valid HTTPS URL")
	}
	if cfg.OBank.ResultURL == "" || validateOBankURL(cfg.OBank.ResultURL, cfg.IsDevelopment()) != nil {
		problems = append(problems, "OBANK_RESULT_URL must be a valid HTTPS callback URL")
	}
	if cfg.OBank.ReturnURL == "" || validateOBankURL(cfg.OBank.ReturnURL, cfg.IsDevelopment()) != nil {
		problems = append(problems, "OBANK_RETURN_URL must be a valid HTTPS billing return URL")
	}
	if cfg.IsStaging() && !cfg.OBank.Test {
		problems = append(problems, "OBANK_TEST must be true in staging")
	}
	return problems
}

func isOBankSandboxURL(value string) bool {
	parsed, err := url.Parse(strings.TrimSpace(value))
	return err == nil && strings.EqualFold(parsed.Scheme, "https") && strings.EqualFold(parsed.Hostname(), "mw-api-test.dengi.kg") && parsed.Path == "/api/json/json.php" && parsed.RawQuery == "" && parsed.Fragment == ""
}

func validateOBankURL(value string, allowLocalHTTP bool) error {
	parsed, err := url.Parse(strings.TrimSpace(value))
	if err != nil || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return errors.New("invalid URL")
	}
	if parsed.Scheme == "https" {
		return nil
	}
	if allowLocalHTTP && parsed.Scheme == "http" && isLoopbackHostname(parsed.Hostname()) {
		return nil
	}
	return errors.New("HTTPS is required")
}

func isLoopbackHostname(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
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

func isNarrowTrustedProxyPrefix(prefix netip.Prefix) bool {
	if !prefix.IsValid() || prefix.Addr().IsUnspecified() {
		return false
	}
	minimumBits := 64
	if prefix.Addr().Is4() {
		minimumBits = 16
	}
	return prefix.Bits() >= minimumBits
}

func validateVerifiedDatabaseTLS(databaseURL string) error {
	poolConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return errors.New("DATABASE_URL must be a valid PostgreSQL URL with verified TLS in staging and production")
	}
	if !usesVerifiedPostgresTLS(poolConfig.ConnConfig.TLSConfig) {
		return errors.New("DATABASE_URL must use sslmode=verify-full in staging and production")
	}
	for _, fallback := range poolConfig.ConnConfig.Fallbacks {
		if !usesVerifiedPostgresTLS(fallback.TLSConfig) {
			return errors.New("DATABASE_URL must use sslmode=verify-full for every staging and production database host")
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
	endpoint := strings.TrimSpace(cfg.NikitaAPIURL)
	if endpoint == "" {
		problems = append(problems, "NIKITA_API_URL is required")
	} else {
		apiURL, err := url.Parse(endpoint)
		if err != nil || apiURL.Scheme == "" || apiURL.Host == "" {
			problems = append(problems, "NIKITA_API_URL must be a valid absolute URL")
		} else if cfg.IsProductionLike() && !isOfficialNikitaAPIURL(apiURL) {
			problems = append(problems, "NIKITA_API_URL must be the official HTTPS endpoint https://smspro.nikita.kg/api/message in staging and production")
		}
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

func isOfficialNikitaAPIURL(apiURL *url.URL) bool {
	if apiURL == nil || !strings.EqualFold(apiURL.Scheme, "https") || apiURL.User != nil || apiURL.Opaque != "" {
		return false
	}
	if !strings.EqualFold(apiURL.Hostname(), "smspro.nikita.kg") || (apiURL.Port() != "" && apiURL.Port() != "443") {
		return false
	}
	return apiURL.EscapedPath() == "/api/message" && apiURL.RawQuery == "" && !apiURL.ForceQuery && apiURL.Fragment == ""
}

func isUnsafeSigningKey(value string) bool {
	trimmed := strings.TrimSpace(value)
	if len(trimmed) < minProductionSigningKeyLength {
		return true
	}
	lower := strings.ToLower(trimmed)
	return strings.Contains(lower, "change-this") ||
		strings.Contains(lower, "dev-only") ||
		strings.Contains(lower, "secret") ||
		hasRepeatedSigningKeyPattern(trimmed) ||
		hasLongSequentialSigningKeyRun(trimmed) ||
		estimatedSigningKeyEntropyBits(trimmed) < minProductionSigningKeyEntropyBits
}

// estimatedSigningKeyEntropyBits screens out low-diversity values; it cannot prove how a key was generated.
func estimatedSigningKeyEntropyBits(value string) float64 {
	var counts [256]int
	for i := 0; i < len(value); i++ {
		counts[value[i]]++
	}

	entropyPerByte := 0.0
	for _, count := range counts {
		if count == 0 {
			continue
		}
		probability := float64(count) / float64(len(value))
		entropyPerByte -= probability * math.Log2(probability)
	}
	return entropyPerByte * float64(len(value))
}

func hasRepeatedSigningKeyPattern(value string) bool {
	for period := 1; period <= 16 && period*2 <= len(value); period++ {
		repeated := true
		for i := period; i < len(value); i++ {
			if value[i] != value[i%period] {
				repeated = false
				break
			}
		}
		if repeated {
			return true
		}
	}
	return false
}

func hasLongSequentialSigningKeyRun(value string) bool {
	const minimumSequentialRun = 12
	previousRank, previousIsSequenceCharacter := signingKeyCharacterRank(value[0])
	direction := 0
	runLength := 1

	for i := 1; i < len(value); i++ {
		rank, isSequenceCharacter := signingKeyCharacterRank(value[i])
		if !previousIsSequenceCharacter || !isSequenceCharacter {
			previousRank = rank
			previousIsSequenceCharacter = isSequenceCharacter
			direction = 0
			runLength = 1
			continue
		}

		delta := rank - previousRank
		if delta == 1 || delta == -1 {
			if direction == delta {
				runLength++
			} else {
				direction = delta
				runLength = 2
			}
			if runLength >= minimumSequentialRun {
				return true
			}
		} else {
			direction = 0
			runLength = 1
		}
		previousRank = rank
		previousIsSequenceCharacter = isSequenceCharacter
	}
	return false
}

func signingKeyCharacterRank(value byte) (int, bool) {
	switch {
	case value >= '0' && value <= '9':
		return int(value - '0'), true
	case value >= 'a' && value <= 'z':
		return int(value-'a') + 10, true
	case value >= 'A' && value <= 'Z':
		return int(value-'A') + 10, true
	default:
		return 0, false
	}
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

func getEnvBool(key string, fallback bool) (bool, error) {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value == "" {
		return fallback, nil
	}
	switch value {
	case "1", "true", "yes", "on":
		return true, nil
	case "0", "false", "no", "off":
		return false, nil
	default:
		return false, fmt.Errorf("invalid boolean value for %s", key)
	}
}

func getEnv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func getEnvInt(key string, fallback int) (int, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("invalid integer value for %s", key)
	}
	return parsed, nil
}

func getDurationMinutes(key string, fallback int) (time.Duration, error) {
	minutes, err := getEnvInt(key, fallback)
	if err != nil {
		return 0, err
	}
	const maxInt64 = int64(1<<63 - 1)
	const minInt64 = -1 << 63
	maxMinutes := maxInt64 / int64(time.Minute)
	minMinutes := minInt64 / int64(time.Minute)
	if int64(minutes) < minMinutes || int64(minutes) > maxMinutes {
		return 0, fmt.Errorf("%s is outside the supported duration range", key)
	}
	return time.Duration(minutes) * time.Minute, nil
}

func getMegabytes(key string, fallback int) (int64, error) {
	megabytes, err := getEnvInt(key, fallback)
	if err != nil {
		return 0, err
	}
	const bytesPerMegabyte = int64(1024 * 1024)
	const maxInt64 = int64(1<<63 - 1)
	const minInt64 = -1 << 63
	if int64(megabytes) < minInt64/bytesPerMegabyte || int64(megabytes) > maxInt64/bytesPerMegabyte {
		return 0, fmt.Errorf("%s is outside the supported size range", key)
	}
	return int64(megabytes) * bytesPerMegabyte, nil
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
