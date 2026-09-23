package sms

import (
	"context"
	"encoding/xml"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNikitaSenderSendsLoginCode(t *testing.T) {
	var got nikitaMessage
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if r.Header.Get("Content-Type") != "application/xml; charset=utf-8" {
			t.Fatalf("unexpected content type: %q", r.Header.Get("Content-Type"))
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read request: %v", err)
		}
		if err := xml.Unmarshal(body, &got); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		w.Header().Set("Content-Type", "application/xml")
		_, _ = w.Write([]byte(`<?xml version="1.0"?><response><status>0</status></response>`))
	}))
	defer server.Close()
	sender, err := newNikitaSender(NikitaConfig{
		APIURL:   server.URL,
		Login:    "test-login",
		Password: "test-password",
		Sender:   "SMSPRO.KG",
	}, server.Client())
	if err != nil {
		t.Fatalf("newNikitaSender: %v", err)
	}
	if err := sender.SendLoginCode(context.Background(), "+996700000001", "123456"); err != nil {
		t.Fatalf("SendLoginCode: %v", err)
	}
	if got.Login != "test-login" || got.Password != "test-password" {
		t.Fatalf("unexpected credentials in request: %#v", got)
	}
	if got.Sender != "SMSPRO.KG" || len(got.Phones) != 1 || got.Phones[0] != "+996700000001" {
		t.Fatalf("unexpected recipient/sender: %#v", got)
	}
	if !strings.Contains(got.Text, "123456") {
		t.Fatalf("code is missing from text: %q", got.Text)
	}
	if got.Test != "" {
		t.Fatalf("test flag must be absent by default: %q", got.Test)
	}
}

func TestNikitaSenderSupportsTestMode(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var got nikitaMessage
		if err := xml.Unmarshal(body, &got); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		if got.Test != "1" {
			t.Fatalf("expected test flag, got %q", got.Test)
		}
		_, _ = w.Write([]byte(`<response><status>0</status></response>`))
	}))
	defer server.Close()
	sender, err := newNikitaSender(NikitaConfig{APIURL: server.URL, Login: "login", Password: "password", Sender: "SMSPRO.KG", TestMode: true}, server.Client())
	if err != nil {
		t.Fatalf("newNikitaSender: %v", err)
	}
	if err := sender.SendLoginCode(context.Background(), "996700000001", "654321"); err != nil {
		t.Fatalf("SendLoginCode: %v", err)
	}
}

func TestNikitaSenderRejectsProviderError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`<response><status>5</status><message>invalid sender</message></response>`))
	}))
	defer server.Close()
	sender, err := newNikitaSender(NikitaConfig{APIURL: server.URL, Login: "login", Password: "password", Sender: "SMSPRO.KG"}, server.Client())
	if err != nil {
		t.Fatalf("newNikitaSender: %v", err)
	}
	if err := sender.SendLoginCode(context.Background(), "996700000001", "123456"); err == nil {
		t.Fatal("expected provider error")
	}
}
