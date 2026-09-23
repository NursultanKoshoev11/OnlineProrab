package sms

import (
	"context"
	crand "crypto/rand"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultNikitaAPIURL = "https://smspro.nikita.kg/api/message"

type NikitaConfig struct {
	APIURL   string
	Login    string
	Password string
	Sender   string
	TestMode bool
}

type NikitaSender struct {
	config NikitaConfig
	client *http.Client
}

type nikitaMessage struct {
	XMLName  xml.Name `xml:"message"`
	Login    string   `xml:"login"`
	Password string   `xml:"pwd"`
	ID       string   `xml:"id"`
	Sender   string   `xml:"sender"`
	Text     string   `xml:"text"`
	Phones   []string `xml:"phones>phone"`
	Test     string   `xml:"test,omitempty"`
}

type nikitaResponse struct {
	Status  string `xml:"status"`
	Message string `xml:"message"`
}

func NewNikitaSender(cfg NikitaConfig) (*NikitaSender, error) {
	return newNikitaSender(cfg, &http.Client{Timeout: 12 * time.Second})
}

func newNikitaSender(cfg NikitaConfig, client *http.Client) (*NikitaSender, error) {
	cfg.APIURL = strings.TrimSpace(cfg.APIURL)
	if cfg.APIURL == "" {
		cfg.APIURL = defaultNikitaAPIURL
	}
	cfg.Login = strings.TrimSpace(cfg.Login)
	cfg.Password = strings.TrimSpace(cfg.Password)
	cfg.Sender = strings.TrimSpace(cfg.Sender)
	if cfg.Login == "" || cfg.Password == "" || cfg.Sender == "" {
		return nil, errors.New("Nikita credentials and sender are required")
	}
	if client == nil {
		return nil, errors.New("http client is required")
	}
	return &NikitaSender{config: cfg, client: client}, nil
}

func (s *NikitaSender) SendLoginCode(ctx context.Context, phone, code string) error {
	phone = strings.TrimSpace(phone)
	code = strings.TrimSpace(code)
	if phone == "" || code == "" {
		return errors.New("phone and code are required")
	}
	id, err := newNikitaMessageID()
	if err != nil {
		return fmt.Errorf("create Nikita message id: %w", err)
	}
	msg := nikitaMessage{
		Login:    s.config.Login,
		Password: s.config.Password,
		ID:       id,
		Sender:   s.config.Sender,
		Text:     fmt.Sprintf("STROY verification code: %s. Do not share this code.", code),
		Phones:   []string{phone},
	}
	if s.config.TestMode {
		msg.Test = "1"
	}
	body, err := xml.Marshal(msg)
	if err != nil {
		return fmt.Errorf("encode Nikita request: %w", err)
	}
	body = append([]byte(xml.Header), body...)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.config.APIURL, strings.NewReader(string(body)))
	if err != nil {
		return fmt.Errorf("create Nikita request: %w", err)
	}
	req.Header.Set("Content-Type", "application/xml; charset=utf-8")
	req.Header.Set("Accept", "application/xml")
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("send Nikita request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		return fmt.Errorf("Nikita returned HTTP status %d", resp.StatusCode)
	}
	var result nikitaResponse
	if err := xml.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&result); err != nil {
		return fmt.Errorf("decode Nikita response: %w", err)
	}
	if result.Status != "0" {
		return fmt.Errorf("Nikita rejected SMS with status %s", result.Status)
	}
	return nil
}

func newNikitaMessageID() (string, error) {
	var raw [5]byte
	if _, err := crand.Read(raw[:]); err != nil {
		return "", err
	}
	return "S" + hex.EncodeToString(raw[:]), nil
}
