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
	Send(ctx context.Context, targets []Target, title, body string, data map[string]string) error
}

// Target identifies one FCM destination. Firebase Installation IDs (FIDs)
// are used by current Firebase clients; legacy registration tokens remain
// supported so already registered devices keep receiving notifications.
type Target struct {
	ID   string
	Type string
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
	Token        string            `json:"token,omitempty"`
	FID          string            `json:"fid,omitempty"`
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

func (s *FirebaseSender) Send(ctx context.Context, targets []Target, title, body string, data map[string]string) error {
	if s == nil || s.client == nil {
		return fmt.Errorf("Firebase sender is not configured")
	}
	seen := make(map[Target]struct{}, len(targets))
	for _, target := range targets {
		target.ID = strings.TrimSpace(target.ID)
		target.Type = strings.TrimSpace(target.Type)
		if target.ID == "" {
			continue
		}
		if target.Type == "" {
			target.Type = "token"
		}
		if target.Type != "token" && target.Type != "fid" {
			return fmt.Errorf("unsupported Firebase target type %q", target.Type)
		}
		if _, ok := seen[target]; ok {
			continue
		}
		seen[target] = struct{}{}
		if err := s.sendOne(ctx, target, title, body, data); err != nil {
			return err
		}
	}
	return nil
}

func (s *FirebaseSender) sendOne(ctx context.Context, target Target, title, body string, data map[string]string) error {
	message := fcmMessage{
		Notification: fcmNotification{Title: title, Body: body},
		Data:         data,
		Android:      &fcmAndroidConfig{Priority: "HIGH"},
		APNS:         &fcmAPNSConfig{Headers: map[string]string{"apns-priority": "10"}},
	}
	if target.Type == "fid" {
		message.FID = target.ID
	} else {
		message.Token = target.ID
	}
	payload, err := json.Marshal(fcmRequest{Message: message})
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
