package sms

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const twilioAPIBaseURL = "https://api.twilio.com"

type Sender interface {
	SendLoginCode(ctx context.Context, phone, code string) error
}

type TwilioConfig struct {
	AccountSID          string
	APIKeySID           string
	APIKeySecret        string
	From                string
	MessagingServiceSID string
}

type TwilioSender struct {
	config  TwilioConfig
	client  *http.Client
	baseURL string
}

func NewTwilioSender(cfg TwilioConfig) (*TwilioSender, error) {
	return newTwilioSender(cfg, &http.Client{Timeout: 10 * time.Second}, twilioAPIBaseURL)
}

func newTwilioSender(cfg TwilioConfig, client *http.Client, baseURL string) (*TwilioSender, error) {
	cfg.AccountSID = strings.TrimSpace(cfg.AccountSID)
	cfg.APIKeySID = strings.TrimSpace(cfg.APIKeySID)
	cfg.APIKeySecret = strings.TrimSpace(cfg.APIKeySecret)
	cfg.From = strings.TrimSpace(cfg.From)
	cfg.MessagingServiceSID = strings.TrimSpace(cfg.MessagingServiceSID)
	if cfg.AccountSID == "" || cfg.APIKeySID == "" || cfg.APIKeySecret == "" {
		return nil, errors.New("twilio credentials are incomplete")
	}
	if (cfg.From == "") == (cfg.MessagingServiceSID == "") {
		return nil, errors.New("exactly one twilio sender must be configured")
	}
	if client == nil {
		return nil, errors.New("http client is required")
	}
	if strings.TrimSpace(baseURL) == "" {
		return nil, errors.New("twilio base URL is required")
	}
	return &TwilioSender{config: cfg, client: client, baseURL: strings.TrimRight(baseURL, "/")}, nil
}

func (s *TwilioSender) SendLoginCode(ctx context.Context, phone, code string) error {
	phone = strings.TrimSpace(phone)
	code = strings.TrimSpace(code)
	if phone == "" || code == "" {
		return errors.New("phone and code are required")
	}

	form := url.Values{}
	form.Set("To", phone)
	form.Set("Body", fmt.Sprintf("OnlinePRorab: код входа %s. Действует 5 минут.", code))
	if s.config.MessagingServiceSID != "" {
		form.Set("MessagingServiceSid", s.config.MessagingServiceSID)
	} else {
		form.Set("From", s.config.From)
	}

	endpoint := fmt.Sprintf("%s/2010-04-01/Accounts/%s/Messages.json", s.baseURL, url.PathEscape(s.config.AccountSID))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return fmt.Errorf("create SMS request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	req.SetBasicAuth(s.config.APIKeySID, s.config.APIKeySecret)

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("send SMS request: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("SMS provider returned status %d", resp.StatusCode)
	}
	return nil
}
