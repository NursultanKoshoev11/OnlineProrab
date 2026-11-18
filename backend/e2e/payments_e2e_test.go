//go:build e2e

package e2e

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	paymentPhoneA = "+996700000021"
	paymentPhoneB = "+996700000022"
	paymentPhoneC = "+996700000023"
)

type fakeOBankCall struct {
	Command string `json:"command"`
	Request struct {
		Data map[string]any `json:"data"`
	} `json:"request"`
}

type checkoutResult struct {
	status int
	body   []byte
	err    error
}

func TestSubscriptionPaymentsEndToEnd(t *testing.T) {
	client := newE2EClient(t)
	fakeBankURL := strings.TrimRight(os.Getenv("E2E_FAKE_OBANK_URL"), "/")
	if fakeBankURL == "" {
		fakeBankURL = "http://127.0.0.1:8091"
	}
	waitForReady(t, client)
	resetFakeOBank(t, fakeBankURL)

	userA := login(t, client, paymentPhoneA)
	userB := login(t, client, paymentPhoneB)
	userC := login(t, client, paymentPhoneC)
	var happyOrderID string

	t.Run("standard monthly happy path and idempotency", func(t *testing.T) {
		key := "payment-happy-standard-20261118"
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/subscriptions/checkout", userA.accessToken, map[string]string{
			"plan_id": "standard", "billing_period": "month", "idempotency_key": key,
		})
		assertStatus(t, status, body, http.StatusCreated)
		first := decodeCheckout(t, body)
		happyOrderID = first.OrderID
		if first.AmountKGS != 3000 || first.Currency != "KGS" || !strings.HasPrefix(first.PaymentURL, "http://fake-obank:8091/pay/") {
			t.Fatalf("unexpected standard checkout: %+v", first)
		}

		status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/subscriptions/checkout", userA.accessToken, map[string]string{
			"plan_id": "standard", "billing_period": "month", "idempotency_key": key,
		})
		assertStatus(t, status, body, http.StatusCreated)
		second := decodeCheckout(t, body)
		if second.OrderID != first.OrderID || second.PaymentURL != first.PaymentURL {
			t.Fatalf("idempotent checkout changed order or link: first=%+v second=%+v", first, second)
		}
		assertFakeOBankCreateCount(t, fakeBankURL, first.OrderID, 1)

		result := obankResultBody("e2e-callback-a", 3, "e2e-only-sid", first.OrderID, first.AmountKGS*100, "KGS", invoiceID(first.PaymentURL), time.Now().UTC(), 1)
		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", result, "application/json")
		assertStatus(t, status, body, http.StatusOK)

		status, body, _ = client.request(t, http.MethodGet, "/api/v1/subscriptions/status", userA.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		active := decodeJSONMap(t, body)
		if active["plan"] != "standard" || active["status"] != "active" || active["billing_period"] != "month" {
			t.Fatalf("subscription did not become active standard/month: %s", body)
		}
		firstPeriodEnd := parseRFC3339Field(t, active, "current_period_end")
		if firstPeriodEnd.Before(time.Now().Add(20*24*time.Hour)) || firstPeriodEnd.After(time.Now().Add(40*24*time.Hour)) {
			t.Fatalf("monthly period end = %v, want about one month ahead", firstPeriodEnd)
		}

		status, body, _ = client.request(t, http.MethodGet, "/api/v1/subscriptions/checkout?order_id="+url.QueryEscape(first.OrderID), userA.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		paid := decodeCheckout(t, body)
		if paid.Status != "paid" {
			t.Fatalf("checkout status = %q, want paid", paid.Status)
		}

		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", result, "application/json")
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/subscriptions/status", userA.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		replayed := decodeJSONMap(t, body)
		if parseRFC3339Field(t, replayed, "current_period_end") != firstPeriodEnd {
			t.Fatalf("replayed callback extended period: before=%v after=%v", firstPeriodEnd, replayed["current_period_end"])
		}
	})

	t.Run("cross-user checkout access is isolated", func(t *testing.T) {
		status, body, _ := client.request(t, http.MethodGet, "/api/v1/subscriptions/checkout?order_id="+url.QueryEscape(happyOrderID), userB.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusNotFound)

		// A's signed callback must not change B's trial subscription.
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/subscriptions/status", userB.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		state := decodeJSONMap(t, body)
		if state["plan"] != "trial" || state["status"] != "trialing" {
			t.Fatalf("user B was activated by user A's callback: %s", body)
		}
	})

	t.Run("invalid callbacks leave the subscription unchanged", func(t *testing.T) {
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/subscriptions/checkout", userB.accessToken, map[string]string{
			"plan_id": "standard", "billing_period": "month", "idempotency_key": "payment-invalid-callback-20261118",
		})
		assertStatus(t, status, body, http.StatusCreated)
		checkout := decodeCheckout(t, body)
		invoice := invoiceID(checkout.PaymentURL)

		beforeStatus := subscriptionSnapshot(t, client, userB)
		wrongSignature := obankResultBody("e2e-invalid-signature", 3, "e2e-only-sid", checkout.OrderID, checkout.AmountKGS*100, "KGS", invoice, time.Now().UTC(), 1)
		var wrongSignaturePayload map[string]any
		if err := json.Unmarshal(wrongSignature, &wrongSignaturePayload); err != nil {
			t.Fatal(err)
		}
		wrongSignaturePayload["hash"] = strings.Repeat("0", 32)
		var err error
		wrongSignature, err = json.Marshal(wrongSignaturePayload)
		if err != nil {
			t.Fatal(err)
		}
		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", wrongSignature, "application/json")
		assertStatus(t, status, body, http.StatusUnauthorized)
		assertSubscriptionSnapshot(t, client, userB, beforeStatus)

		wrongAmount := obankResultBody("e2e-invalid-amount", 3, "e2e-only-sid", checkout.OrderID, checkout.AmountKGS*100+1, "KGS", invoice, time.Now().UTC(), 1)
		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", wrongAmount, "application/json")
		assertStatus(t, status, body, http.StatusUnprocessableEntity)
		assertSubscriptionSnapshot(t, client, userB, beforeStatus)

		wrongCurrency := obankResultBody("e2e-invalid-currency", 3, "e2e-only-sid", checkout.OrderID, checkout.AmountKGS*100, "USD", invoice, time.Now().UTC(), 1)
		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", wrongCurrency, "application/json")
		assertStatus(t, status, body, http.StatusUnprocessableEntity)
		assertSubscriptionSnapshot(t, client, userB, beforeStatus)

		stale := obankResultBody("e2e-stale-callback", 3, "e2e-only-sid", checkout.OrderID, checkout.AmountKGS*100, "KGS", invoice, time.Now().Add(-8*24*time.Hour).UTC(), 1)
		status, body, _ = client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", stale, "application/json")
		assertStatus(t, status, body, http.StatusUnauthorized)
		assertSubscriptionSnapshot(t, client, userB, beforeStatus)
	})

	t.Run("status polling activates a paid order", func(t *testing.T) {
		status, body := setFakeOBankNextStatus(t, fakeBankURL, "approved")
		assertStatus(t, status, body, http.StatusOK)

		status, body, _ = client.request(t, http.MethodGet, "/api/v1/subscriptions/checkout?order_id="+url.QueryEscape(orderIDForUser(t, client, userB, "payment-invalid-callback-20261118")), userB.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		checkout := decodeCheckout(t, body)
		if checkout.Status != "paid" {
			t.Fatalf("polled checkout status = %q, want paid", checkout.Status)
		}
		state := subscriptionSnapshot(t, client, userB)
		if state["plan"] != "standard" || state["status"] != "active" || state["billing_period"] != "month" {
			t.Fatalf("status polling did not activate standard/month: %#v", state)
		}
	})

	t.Run("five concurrent requests create one max yearly invoice", func(t *testing.T) {
		key := "payment-concurrent-max-year-20261118"
		results := make(chan checkoutResult, 5)
		start := make(chan struct{})
		var wait sync.WaitGroup
		for i := 0; i < 5; i++ {
			wait.Add(1)
			go func() {
				defer wait.Done()
				<-start
				status, body, err := rawJSONRequest(client, http.MethodPost, "/api/v1/subscriptions/checkout", userC.accessToken, map[string]string{
					"plan_id": "max", "billing_period": "year", "idempotency_key": key,
				})
				results <- checkoutResult{status: status, body: body, err: err}
			}()
		}
		close(start)
		wait.Wait()

		var order Checkout
		for i := 0; i < 5; i++ {
			result := <-results
			if result.err != nil {
				t.Fatalf("concurrent checkout request failed: %v", result.err)
			}
			assertStatus(t, result.status, result.body, http.StatusCreated)
			current := decodeCheckout(t, result.body)
			if current.AmountKGS != 51000 || current.BillingPeriod != "year" || current.PlanID != "max" {
				t.Fatalf("unexpected max yearly checkout: %+v", current)
			}
			if i == 0 {
				order = current
			} else if current.OrderID != order.OrderID {
				t.Fatalf("concurrent request returned a different order: %q vs %q", current.OrderID, order.OrderID)
			}
		}
		assertFakeOBankCreateCount(t, fakeBankURL, order.OrderID, 1)

		result := obankResultBody("e2e-callback-c", 3, "e2e-only-sid", order.OrderID, order.AmountKGS*100, "KGS", invoiceID(order.PaymentURL), time.Now().UTC(), 1)
		status, body, _ := client.request(t, http.MethodPost, "/api/v1/payments/obank/result", "", result, "application/json")
		assertStatus(t, status, body, http.StatusOK)
		state := subscriptionSnapshot(t, client, userC)
		if state["plan"] != "max" || state["status"] != "active" || state["billing_period"] != "year" {
			t.Fatalf("max yearly payment did not activate: %#v", state)
		}
		periodEnd := parseRFC3339Field(t, state, "current_period_end")
		if periodEnd.Before(time.Now().Add(11*30*24*time.Hour)) || periodEnd.After(time.Now().Add(14*30*24*time.Hour)) {
			t.Fatalf("yearly period end = %v, want about one year ahead", periodEnd)
		}
	})
}

type Checkout struct {
	OrderID       string `json:"order_id"`
	Status        string `json:"status"`
	PlanID        string `json:"plan_id"`
	BillingPeriod string `json:"billing_period"`
	AmountKGS     int    `json:"amount_kgs"`
	Currency      string `json:"currency"`
	PaymentURL    string `json:"payment_url"`
}

func newE2EClient(t *testing.T) *apiClient {
	t.Helper()
	baseURL := strings.TrimRight(os.Getenv("E2E_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8080"
	}
	return &apiClient{baseURL: baseURL, http: &http.Client{Timeout: 20 * time.Second}}
}

func decodeCheckout(t *testing.T, body []byte) Checkout {
	t.Helper()
	var response Checkout
	decodeJSON(t, body, &response)
	if response.OrderID == "" || response.Status == "" {
		t.Fatalf("invalid checkout response: %s", body)
	}
	return response
}

func decodeJSONMap(t *testing.T, body []byte) map[string]any {
	t.Helper()
	var response map[string]any
	decodeJSON(t, body, &response)
	return response
}

func resetFakeOBank(t *testing.T, baseURL string) {
	t.Helper()
	request, err := http.NewRequest(http.MethodDelete, baseURL+"/calls", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("fake O!Bank is not reachable at %s: %v", baseURL, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("reset fake O!Bank returned %d", response.StatusCode)
	}
}

func readFakeOBankCalls(t *testing.T, baseURL string) []fakeOBankCall {
	t.Helper()
	response, err := http.Get(baseURL + "/calls")
	if err != nil {
		t.Fatalf("read fake O!Bank calls: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("read fake O!Bank calls returned %d", response.StatusCode)
	}
	var payload struct {
		Calls []fakeOBankCall `json:"calls"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode fake O!Bank calls: %v", err)
	}
	return payload.Calls
}

func assertFakeOBankCreateCount(t *testing.T, baseURL, orderID string, want int) {
	t.Helper()
	got := 0
	for _, call := range readFakeOBankCalls(t, baseURL) {
		if call.Command == "createInvoice" && fmt.Sprint(call.Request.Data["order_id"]) == orderID {
			got++
		}
	}
	if got != want {
		t.Fatalf("fake O!Bank createInvoice calls for %s = %d, want %d", orderID, got, want)
	}
}

func setFakeOBankNextStatus(t *testing.T, baseURL, status string) (int, []byte) {
	t.Helper()
	body := mustMarshal(t, map[string]string{"status": status})
	request, err := http.NewRequest(http.MethodPut, baseURL+"/control/status", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatalf("set fake O!Bank status: %v", err)
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response.StatusCode, responseBody
}

func obankResultBody(transactionID string, status int, siteID, orderID string, amount int, currency, invoice string, issuedAt time.Time, testFlag int) []byte {
	mktime := strconv.FormatInt(issuedAt.Unix(), 10)
	values := []string{transactionID, strconv.Itoa(status), siteID, orderID, strconv.Itoa(amount), currency, mktime, strconv.Itoa(testFlag)}
	hash := hmac.New(md5.New, []byte("e2e-only-password"))
	_, _ = hash.Write([]byte(strings.Join(values, ":::")))
	payload := map[string]any{
		"trans_id": transactionID, "status_pay": status, "site_id": siteID, "order_id": orderID,
		"amount": amount, "currency": currency, "mktime": mktime, "test": testFlag,
		"invoice_id": invoice, "hash": hex.EncodeToString(hash.Sum(nil)),
	}
	body, err := json.Marshal(payload)
	if err != nil {
		panic(err)
	}
	return body
}

func invoiceID(paymentURL string) string {
	parsed, err := url.Parse(paymentURL)
	if err != nil {
		return ""
	}
	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
	if len(parts) == 2 && parts[0] == "pay" {
		return parts[1]
	}
	return ""
}

func subscriptionSnapshot(t *testing.T, client *apiClient, user session) map[string]any {
	t.Helper()
	status, body, _ := client.request(t, http.MethodGet, "/api/v1/subscriptions/status", user.accessToken, nil, "")
	assertStatus(t, status, body, http.StatusOK)
	return decodeJSONMap(t, body)
}

func assertSubscriptionSnapshot(t *testing.T, client *apiClient, user session, before map[string]any) {
	t.Helper()
	after := subscriptionSnapshot(t, client, user)
	for _, field := range []string{"plan", "status", "billing_period", "current_period_end"} {
		if after[field] != before[field] {
			t.Fatalf("subscription field %s changed: before=%v after=%v", field, before[field], after[field])
		}
	}
}

func parseRFC3339Field(t *testing.T, value map[string]any, field string) time.Time {
	t.Helper()
	text, ok := value[field].(string)
	if !ok {
		t.Fatalf("subscription field %q is not a string: %#v", field, value)
	}
	parsed, err := time.Parse(time.RFC3339, text)
	if err != nil {
		t.Fatalf("parse subscription field %q=%q: %v", field, text, err)
	}
	return parsed
}

func orderIDForUser(t *testing.T, client *apiClient, user session, key string) string {
	t.Helper()
	// The API intentionally does not expose idempotency-key lookup. Repeating
	// the same request is the public idempotent lookup and returns the order.
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/subscriptions/checkout", user.accessToken, map[string]string{
		"plan_id": "standard", "billing_period": "month", "idempotency_key": key,
	})
	assertStatus(t, status, body, http.StatusCreated)
	return decodeCheckout(t, body).OrderID
}

func rawJSONRequest(client *apiClient, method, path, token string, value any) (int, []byte, error) {
	body, err := json.Marshal(value)
	if err != nil {
		return 0, nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, method, client.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	response, err := client.http.Do(request)
	if err != nil {
		return 0, nil, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	return response.StatusCode, responseBody, err
}
