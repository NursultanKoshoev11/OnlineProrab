package notifications

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

func TestFirebaseSenderUsesCorrectTargetField(t *testing.T) {
	var messages []map[string]any
	sender := &FirebaseSender{
		projectID: "test-project",
		client: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			if request.Method != http.MethodPost {
				t.Errorf("method = %s, want POST", request.Method)
			}
			if request.URL.Path != "/v1/projects/test-project/messages:send" {
				t.Errorf("path = %s, want Firebase send endpoint", request.URL.Path)
			}
			body, err := io.ReadAll(request.Body)
			if err != nil {
				return nil, err
			}
			var payload struct {
				Message map[string]any `json:"message"`
			}
			if err := json.Unmarshal(body, &payload); err != nil {
				return nil, err
			}
			messages = append(messages, payload.Message)
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader(`{"name":"sent"}`)),
				Request:    request,
			}, nil
		})},
	}

	err := sender.Send(context.Background(), []Target{
		{ID: "Abcdefghijklmnopqrstuv", Type: "fid"},
		{ID: "legacy-fcm-registration-token", Type: "token"},
	}, "Новый расход", "Куплен цемент", nil)
	if err != nil {
		t.Fatalf("send notifications: %v", err)
	}
	if len(messages) != 2 {
		t.Fatalf("sent %d messages, want 2", len(messages))
	}
	if got := messages[0]["fid"]; got != "Abcdefghijklmnopqrstuv" {
		t.Fatalf("FID message target = %#v", got)
	}
	if _, ok := messages[0]["token"]; ok {
		t.Fatal("FID message unexpectedly contains token target")
	}
	if got := messages[1]["token"]; got != "legacy-fcm-registration-token" {
		t.Fatalf("legacy message target = %#v", got)
	}
	if _, ok := messages[1]["fid"]; ok {
		t.Fatal("legacy message unexpectedly contains FID target")
	}
}

func TestFirebaseSenderRejectsUnknownTargetType(t *testing.T) {
	sender := &FirebaseSender{client: &http.Client{}}
	err := sender.Send(context.Background(), []Target{{ID: "value", Type: "topic"}}, "title", "body", nil)
	if err == nil {
		t.Fatal("expected unknown target type to be rejected")
	}
}
