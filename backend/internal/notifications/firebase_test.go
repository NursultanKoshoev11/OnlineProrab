package notifications

import (
	"context"
	"encoding/json"
	"errors"
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

// One removed installation must not stop delivery to the user's other
// devices, and the caller must learn which installation to forget.
func TestFirebaseSenderContinuesPastUnregisteredTarget(t *testing.T) {
	var delivered []string
	sender := &FirebaseSender{
		projectID: "test-project",
		client: &http.Client{Transport: roundTripFunc(func(request *http.Request) (*http.Response, error) {
			var body struct {
				Message map[string]any `json:"message"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Fatalf("decode request: %v", err)
			}
			fid, _ := body.Message["fid"].(string)
			if fid == "stale-fid" {
				return &http.Response{StatusCode: http.StatusNotFound, Status: "404 Not Found", Body: io.NopCloser(strings.NewReader(`{"error":{"code":404,"message":"NotRegistered","status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`))}, nil
			}
			if fid == "broken-fid" {
				return &http.Response{StatusCode: http.StatusInternalServerError, Status: "500 Internal Server Error", Body: io.NopCloser(strings.NewReader(`{}`))}, nil
			}
			delivered = append(delivered, fid)
			return &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Body: io.NopCloser(strings.NewReader(`{}`))}, nil
		})},
	}

	err := sender.Send(context.Background(), []Target{
		{ID: "stale-fid", Type: "fid"},
		{ID: "broken-fid", Type: "fid"},
		{ID: "live-fid", Type: "fid"},
	}, "title", "body", nil)

	if len(delivered) != 1 || delivered[0] != "live-fid" {
		t.Fatalf("delivered = %v, want the live device after the failing ones", delivered)
	}
	var sendErr *SendError
	if !errors.As(err, &sendErr) {
		t.Fatalf("err = %v, want *SendError", err)
	}
	if len(sendErr.Errors) != 2 {
		t.Fatalf("errors = %v, want 2", sendErr.Errors)
	}
	if len(sendErr.Unregistered) != 1 || sendErr.Unregistered[0].ID != "stale-fid" {
		t.Fatalf("unregistered = %v, want only stale-fid", sendErr.Unregistered)
	}
}
