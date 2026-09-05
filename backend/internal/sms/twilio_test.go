package sms

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

const (
	testAccountSID = "AC0000000000"
	testAPIKeySID  = "SK0000000000"
	testCredential = "unit-test-credential-value"
)

func TestTwilioSenderSendsLoginCode(t *testing.T) {
	var gotForm url.Values
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.URL.Path != "/2010-04-01/Accounts/AC0000000000/Messages.json" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		username, credential, ok := r.BasicAuth()
		if !ok || username != testAPIKeySID || credential != testCredential {
			t.Fatal("unexpected basic auth")
		}
		if err := r.ParseForm(); err != nil {
			t.Fatalf("ParseForm: %v", err)
		}
		gotForm = r.PostForm
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"sid":"SM000"}`))
	}))
	defer server.Close()

	sender, err := newTwilioSender(TwilioConfig{
		AccountSID:   testAccountSID,
		APIKeySID:    testAPIKeySID,
		APIKeySecret: testCredential,
		From:         "+15550000000",
	}, server.Client(), server.URL)
	if err != nil {
		t.Fatalf("newTwilioSender: %v", err)
	}

	if err := sender.SendLoginCode(context.Background(), "+996700000000", "123456"); err != nil {
		t.Fatalf("SendLoginCode: %v", err)
	}
	if gotForm.Get("To") != "+996700000000" {
		t.Fatalf("unexpected To: %q", gotForm.Get("To"))
	}
	if gotForm.Get("From") != "+15550000000" {
		t.Fatalf("unexpected From: %q", gotForm.Get("From"))
	}
	if !strings.Contains(gotForm.Get("Body"), "123456") {
		t.Fatal("message body does not contain code")
	}
}

func TestTwilioSenderUsesMessagingService(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Fatalf("ParseForm: %v", err)
		}
		if r.PostForm.Get("MessagingServiceSid") != "MG0000000000" {
			t.Fatal("unexpected MessagingServiceSid")
		}
		if r.PostForm.Get("From") != "" {
			t.Fatal("From must be omitted when MessagingServiceSid is configured")
		}
		w.WriteHeader(http.StatusCreated)
	}))
	defer server.Close()

	sender, err := newTwilioSender(TwilioConfig{
		AccountSID:          testAccountSID,
		APIKeySID:           testAPIKeySID,
		APIKeySecret:        testCredential,
		MessagingServiceSID: "MG0000000000",
	}, server.Client(), server.URL)
	if err != nil {
		t.Fatalf("newTwilioSender: %v", err)
	}
	if err := sender.SendLoginCode(context.Background(), "+996700000000", "654321"); err != nil {
		t.Fatalf("SendLoginCode: %v", err)
	}
}

func TestTwilioSenderDoesNotExposeProviderBodyInError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"message":"provider-internal-detail"}`))
	}))
	defer server.Close()

	sender, err := newTwilioSender(TwilioConfig{
		AccountSID:   testAccountSID,
		APIKeySID:    testAPIKeySID,
		APIKeySecret: testCredential,
		From:         "+15550000000",
	}, server.Client(), server.URL)
	if err != nil {
		t.Fatalf("newTwilioSender: %v", err)
	}
	err = sender.SendLoginCode(context.Background(), "+996700000000", "123456")
	if err == nil {
		t.Fatal("expected provider error")
	}
	if strings.Contains(err.Error(), "provider-internal-detail") {
		t.Fatalf("provider response body leaked in error: %v", err)
	}
}
