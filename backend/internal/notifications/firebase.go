package notifications

import (
	"context"
	"encoding/json"
	"errors"
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

// defaultFCMAPIBaseURL is the production Firebase Cloud Messaging API.
const defaultFCMAPIBaseURL = "https://fcm.googleapis.com"

type FirebaseSender struct {
	projectID  string
	client     *http.Client
	apiBaseURL string
}

// WithAPIBaseURL points the sender at another FCM-compatible API, such as the
// recording fake used by the local E2E stack. Configuration validation only
// allows an override in development.
func (s *FirebaseSender) WithAPIBaseURL(baseURL string) *FirebaseSender {
	s.apiBaseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	return s
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

// SendError reports per-target failures after every target was attempted.
// Unregistered lists targets FCM no longer recognizes (the app was removed,
// reinstalled, or its data cleared); callers should forget them.
type SendError struct {
	Unregistered []Target
	Errors       []error
}

func (e *SendError) Error() string {
	return fmt.Sprintf("FCM delivery failed for %d target(s): %v", len(e.Errors), errors.Join(e.Errors...))
}

func (e *SendError) Unwrap() []error {
	return e.Errors
}

// errUnregistered marks an FCM response saying the target no longer exists.
var errUnregistered = errors.New("FCM target is unregistered")

// Send delivers the notification to every target. One stale or failing
// device must never prevent delivery to the user's other devices, so failures
// are collected and returned together as a *SendError.
func (s *FirebaseSender) Send(ctx context.Context, targets []Target, title, body string, data map[string]string) error {
	if s == nil || s.client == nil {
		return fmt.Errorf("Firebase sender is not configured")
	}
	seen := make(map[Target]struct{}, len(targets))
	var failures SendError
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
			failures.Errors = append(failures.Errors, fmt.Errorf("unsupported Firebase target type %q", target.Type))
			continue
		}
		if _, ok := seen[target]; ok {
			continue
		}
		seen[target] = struct{}{}
		if err := s.sendOne(ctx, target, title, body, data); err != nil {
			if errors.Is(err, errUnregistered) {
				failures.Unregistered = append(failures.Unregistered, target)
			}
			failures.Errors = append(failures.Errors, err)
		}
	}
	if len(failures.Errors) > 0 {
		return &failures
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
	baseURL := s.apiBaseURL
	if baseURL == "" {
		baseURL = defaultFCMAPIBaseURL
	}
	endpoint := baseURL + "/v1/projects/" + url.PathEscape(s.projectID) + "/messages:send"
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
		if fcmErrorCode(message) == "UNREGISTERED" {
			return fmt.Errorf("FCM returned %s: %w", response.Status, errUnregistered)
		}
		return fmt.Errorf("FCM returned %s: %s", response.Status, strings.TrimSpace(string(message)))
	}
	return nil
}

// fcmErrorCode extracts the FCM-specific error code from an HTTP v1 error
// response, for example UNREGISTERED for a removed app installation.
func fcmErrorCode(body []byte) string {
	var response struct {
		Error struct {
			Details []struct {
				Type      string `json:"@type"`
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &response) != nil {
		return ""
	}
	for _, detail := range response.Error.Details {
		if detail.Type == "type.googleapis.com/google.firebase.fcm.v1.FcmError" {
			return detail.ErrorCode
		}
	}
	return ""
}
