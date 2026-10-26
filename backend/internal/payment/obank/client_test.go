package obank

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
)

func TestCreateInvoiceUsesDocumentedSitePayAndAppLink(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("request method = %s, want POST", r.Method)
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("read API request: %v", err)
		}
		if strings.Contains(string(body), `\u0026`) {
			t.Errorf("API request unexpectedly HTML-escaped URL query separators")
		}
		var request struct {
			Cmd     string          `json:"cmd"`
			Version int             `json:"version"`
			SID     string          `json:"sid"`
			Mktime  string          `json:"mktime"`
			Lang    string          `json:"lang"`
			Data    json.RawMessage `json:"data"`
			Hash    string          `json:"hash"`
		}
		if err := json.Unmarshal(body, &request); err != nil {
			t.Errorf("decode API request: %v", err)
		}
		stamp, err := strconv.ParseInt(request.Mktime, 10, 64)
		if err != nil || len(request.Mktime) != 13 || time.Since(time.UnixMilli(stamp)) > time.Minute {
			t.Errorf("API mktime = %q, want a recent Unix timestamp in milliseconds", request.Mktime)
		}
		unsigned, err := marshalAPIJSON(apiRequest{
			Cmd: request.Cmd, Version: request.Version, SID: request.SID,
			Mktime: request.Mktime, Lang: request.Lang, Data: request.Data,
		})
		if err != nil {
			t.Errorf("marshal unsigned API request: %v", err)
		}
		if request.Hash != hmacMD5Hex(unsigned, "test-password") {
			t.Errorf("API request signature does not match the unsigned JSON body")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":{"invoice_id":"inv-123","site_pay":"https://dengi.kg/pay/inv-123","link_app":"https://o.kg/l/a?t=wl_unpbill&id=inv-123"}}`))
	}))
	defer server.Close()

	invoice, err := CreateInvoice(context.Background(), config.OBankConfig{
		SID:        "test-sid",
		Password:   "test-password",
		APIURL:     server.URL,
		APIVersion: 1005,
	}, CreateInvoiceData{
		OrderID:    "stroy_test",
		Amount:     300000,
		Currency:   "KGS",
		SuccessURL: "https://stroy.com.kg/billing/?order_id=stroy_test&stage=1",
		FailURL:    "https://stroy.com.kg/billing/?order_id=stroy_test&stage=1&payment_result=failed",
		ResultURL:  "https://stroy.com.kg/staging-api/api/v1/payments/obank/result",
	})
	if err != nil {
		t.Fatalf("CreateInvoice() error = %v", err)
	}
	if invoice.ID != "inv-123" {
		t.Errorf("invoice ID = %q, want inv-123", invoice.ID)
	}
	if invoice.PaymentURL != "https://dengi.kg/pay/inv-123" {
		t.Errorf("payment URL = %q, want documented site_pay URL", invoice.PaymentURL)
	}
	if invoice.AppLink != "https://o.kg/l/a?t=wl_unpbill&id=inv-123" {
		t.Errorf("app link = %q, want matching O!Bank deep link", invoice.AppLink)
	}
}

func TestCreateInvoiceAllowsAppLinkWhenSitePayIsUnavailable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":{"invoice_id":123,"link_app":"https://o.kg/l/a?t=wl_unpbill&id=123"}}`))
	}))
	defer server.Close()

	invoice, err := CreateInvoice(context.Background(), config.OBankConfig{
		SID:        "test-sid",
		Password:   "test-password",
		APIURL:     server.URL,
		APIVersion: 1005,
	}, CreateInvoiceData{OrderID: "stroy_test", Amount: 300000, Currency: "KGS"})
	if err != nil {
		t.Fatalf("CreateInvoice() error = %v", err)
	}
	if invoice.PaymentURL != "" || invoice.AppLink == "" {
		t.Fatalf("invoice links = (%q, %q), want app link only", invoice.PaymentURL, invoice.AppLink)
	}
}

func TestValidatePaymentURLAllowsBankQRFragment(t *testing.T) {
	if err := validatePaymentURL("https://test-paylink.dengi.kg/#000201010212"); err != nil {
		t.Fatalf("validatePaymentURL() rejected bank QR fragment: %v", err)
	}
	if err := validatePaymentURL("https://example.com/#000201010212"); err == nil {
		t.Fatal("validatePaymentURL() accepted an untrusted host")
	}
}

func TestVerifyResultUsesSignedCallbackFieldsInOrder(t *testing.T) {
	secret := "callback-test-secret"
	values := []string{"tx-1", "3", "merchant-1", "stroy_order-1", "300000", "KGS", "1793019000", "1"}
	hash := hmacMD5Hex([]byte(strings.Join(values, ":::")), secret)
	body, err := json.Marshal(map[string]any{
		"trans_id": values[0], "status_pay": 3, "site_id": values[2], "order_id": values[3],
		"amount": values[4], "currency": values[5], "mktime": values[6], "test": 1,
		"invoice_id": "inv-1", "hash": hash,
	})
	if err != nil {
		t.Fatal(err)
	}

	result, err := VerifyResult(body, secret)
	if err != nil {
		t.Fatalf("VerifyResult() error = %v", err)
	}
	if result.TransactionID != values[0] || result.Status != 3 || result.AmountKopecks != 300000 || result.Test != 1 {
		t.Errorf("unexpected verified callback fields: %+v", result)
	}
}
