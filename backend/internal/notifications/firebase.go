package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"

// Sender is the small interface used by the API. Keeping it narrow makes the
// HTTP handlers testable without requiring Firebase credentials.
type Sender interface {
	Send(ctx context.Context, tokens []string, title, body string, data map[string]string) error
}

type FirebaseSender struct {
	projectID string
	client    *http.Client
}

func NewFirebaseSender(ctx context.Context, projectID, serviceAccountJSON string) (*FirebaseSender, error) {
	projectID = strings.TrimSpace(projectID)
	serviceAccountJSON = strings.TrimSpace(serviceAccountJSON)
	if projectID == "" || serviceAccountJSON == "" {
		return nil, fmt.Errorf("firebase project ID and service-account JSON are required")
	}
	creds, err := google.CredentialsFromJSON(ctx, []byte(serviceAccountJSON), fcmScope)
	if err != nil {
		return nil, fmt.Errorf("parse Firebase service-account JSON: %w", err)
	}
	return &FirebaseSender{
		projectID: projectID,
		client:    oauth2.NewClient(ctx, creds.TokenSource),
	}, nil
}

type fcmRequest struct {
	Message fcmMessage `json:"message"`
}

type fcmMessage struct {
	Token        string            `json:"token"`
	Notification fcmNotification   `json:"notification"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *fcmAndroidConfig `json:"android,omitempty"`
	APNS         *fcmAPNSConfig    `json:"apns,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmAndroidConfig struct {
	Priority string `json:"priority"`
}

type fcmAPNSConfig struct {
	Headers map[string]string `json:"headers"`
}

func (s *FirebaseSender) Send(ctx context.Context, tokens []string, title, body string, data map[string]string) error {
	if s == nil || s.client == nil {
		return fmt.Errorf("Firebase sender is not configured")
	}
	seen := make(map[string]struct{}, len(tokens))
	for _, token := range tokens {
		token = strings.TrimSpace(token)
		if token == "" {
			continue
		}
		if _, ok := seen[token]; ok {
			continue
		}
		seen[token] = struct{}{}
		if err := s.sendOne(ctx, token, title, body, data); err != nil {
			return err
		}
	}
	return nil
}

func (s *FirebaseSender) sendOne(ctx context.Context, token, title, body string, data map[string]string) error {
	payload, err := json.Marshal(fcmRequest{Message: fcmMessage{
		Token:        token,
		Notification: fcmNotification{Title: title, Body: body},
		Data:         data,
		Android:      &fcmAndroidConfig{Priority: "HIGH"},
		APNS:         &fcmAPNSConfig{Headers: map[string]string{"apns-priority": "10"}},
	}})
	if err != nil {
		return fmt.Errorf("marshal FCM request: %w", err)
	}
	endpoint := "https://fcm.googleapis.com/v1/projects/" + url.PathEscape(s.projectID) + "/messages:send"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(string(payload)))
	if err != nil {
		return fmt.Errorf("create FCM request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("send FCM notification: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		message, _ := io.ReadAll(io.LimitReader(response.Body, 8<<10))
		return fmt.Errorf("FCM returned %s: %s", response.Status, strings.TrimSpace(string(message)))
	}
	return nil
}
