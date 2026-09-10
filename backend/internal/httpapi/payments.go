package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/jackc/pgx/v5"
)

type subscriptionPlanDefinition struct {
	Code       string
	Name       string
	AmountKGS  int64
	PeriodDays int
}

var paidSubscriptionPlans = map[string]subscriptionPlanDefinition{
	"pro":      {Code: "pro", Name: "Pro", AmountKGS: 990, PeriodDays: 30},
	"business": {Code: "business", Name: "Business", AmountKGS: 2990, PeriodDays: 30},
}

type subscriptionCheckoutRequest struct {
	PlanCode string `json:"plan_code"`
	Provider string `json:"provider"`
}

type paymentOrderResponse struct {
	OrderID     string  `json:"order_id"`
	Provider    string  `json:"provider"`
	PlanCode    string  `json:"plan_code"`
	Amount      float64 `json:"amount"`
	Currency    string  `json:"currency"`
	Status      string  `json:"status"`
	PaymentURL  string  `json:"payment_url,omitempty"`
	TestMode    bool    `json:"test_mode"`
	Integration string  `json:"integration_status"`
	ExpiresAt   string  `json:"expires_at"`
}

// SubscriptionCheckout creates a server-owned payment order. The client only
// submits the plan and provider; the amount is always selected on the server.
// Optima's exact create-payment API is intentionally not guessed here: until
// the bank supplies its manual, a configured hosted URL template or the
// development test mode is required.
func SubscriptionCheckout(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	var request subscriptionCheckoutRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 8*1024)).Decode(&request); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	request.PlanCode = strings.ToLower(strings.TrimSpace(request.PlanCode))
	request.Provider = strings.ToLower(strings.TrimSpace(request.Provider))
	plan, ok := paidSubscriptionPlans[request.PlanCode]
	if !ok {
		Error(w, http.StatusBadRequest, "plan_code must be pro or business")
		return
	}
	if request.Provider != "optima" {
		JSON(w, http.StatusUnprocessableEntity, map[string]string{
			"error": "selected payment provider is not configured",
			"code":  "payment_provider_not_configured",
		})
		return
	}

	configuredTemplate := strings.TrimSpace(appState.OptimaPaymentURLTemplate)
	if !appState.PaymentTestMode && configuredTemplate == "" {
		JSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "Optima payment credentials and checkout URL are not configured",
			"code":  "optima_not_configured",
		})
		return
	}

	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" {
		idempotencyKey = "request:" + requestIDFromContext(r.Context())
	}
	if len(idempotencyKey) > 128 {
		Error(w, http.StatusBadRequest, "Idempotency-Key is too long")
		return
	}

	userID := userIDFromContext(r.Context())
	var response paymentOrderResponse
	err := appState.DB.Pool.QueryRow(r.Context(), `
		INSERT INTO payment_orders
		    (user_id, provider, plan_code, amount, currency, status, idempotency_key, expires_at)
		VALUES ($1, $2, $3, $4, 'KGS', 'pending', $5, now() + interval '30 minutes')
		ON CONFLICT (user_id, provider, idempotency_key)
		DO UPDATE SET updated_at = payment_orders.updated_at
		RETURNING id::text, provider, plan_code, amount::float8, currency, status,
		          COALESCE(payment_url, ''), expires_at::text
	`, userID, request.Provider, plan.Code, plan.AmountKGS, idempotencyKey).Scan(
		&response.OrderID,
		&response.Provider,
		&response.PlanCode,
		&response.Amount,
		&response.Currency,
		&response.Status,
		&response.PaymentURL,
		&response.ExpiresAt,
	)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create payment order")
		return
	}

	if configuredTemplate != "" && response.PaymentURL == "" {
		response.PaymentURL = renderOptimaPaymentURL(configuredTemplate, response)
		if _, err := appState.DB.Pool.Exec(r.Context(), `
			UPDATE payment_orders SET payment_url = $2, updated_at = now() WHERE id = $1
		`, response.OrderID, response.PaymentURL); err != nil {
			Error(w, http.StatusInternalServerError, "failed to save payment checkout URL")
			return
		}
	}

	response.TestMode = appState.PaymentTestMode && !appState.IsProduction
	if response.TestMode {
		response.Integration = "test"
	} else {
		response.Integration = "hosted_redirect"
	}
	writeJSON(w, http.StatusCreated, response)
}

func SubscriptionPayment(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/subscriptions/payments/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 0 || parts[0] == "" || len(parts) > 2 {
		Error(w, http.StatusNotFound, "payment order not found")
		return
	}
	orderID := parts[0]
	if len(parts) == 1 && r.Method == http.MethodGet {
		getPaymentOrder(w, r, orderID)
		return
	}
	if len(parts) == 2 && parts[1] == "test-complete" && r.Method == http.MethodPost {
		completeTestPayment(w, r, orderID)
		return
	}
	Error(w, http.StatusMethodNotAllowed, "method not allowed")
}

func getPaymentOrder(w http.ResponseWriter, r *http.Request, orderID string) {
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	var response paymentOrderResponse
	err := appState.DB.Pool.QueryRow(r.Context(), `
		SELECT id::text, provider, plan_code, amount::float8, currency, status,
		       COALESCE(payment_url, ''), expires_at::text
		FROM payment_orders
		WHERE id = $1 AND user_id = $2
	`, orderID, userIDFromContext(r.Context())).Scan(
		&response.OrderID,
		&response.Provider,
		&response.PlanCode,
		&response.Amount,
		&response.Currency,
		&response.Status,
		&response.PaymentURL,
		&response.ExpiresAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		Error(w, http.StatusNotFound, "payment order not found")
		return
	}
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to read payment order")
		return
	}
	response.TestMode = appState.PaymentTestMode && !appState.IsProduction
	response.Integration = "hosted_redirect"
	if response.TestMode {
		response.Integration = "test"
	}
	writeJSON(w, http.StatusOK, response)
}

func completeTestPayment(w http.ResponseWriter, r *http.Request, orderID string) {
	if !appState.PaymentTestMode || appState.IsProduction {
		JSON(w, http.StatusNotFound, map[string]string{
			"error": "test payment is disabled",
			"code":  "test_payment_disabled",
		})
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	ctx := r.Context()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start payment transaction")
		return
	}
	defer tx.Rollback(ctx)

	var status, planCode string
	if err := tx.QueryRow(ctx, `
		SELECT status, plan_code
		FROM payment_orders
		WHERE id = $1 AND user_id = $2
		FOR UPDATE
	`, orderID, userIDFromContext(ctx)).Scan(&status, &planCode); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			Error(w, http.StatusNotFound, "payment order not found")
		} else {
			Error(w, http.StatusInternalServerError, "failed to lock payment order")
		}
		return
	}

	if status != "paid" {
		if _, err := tx.Exec(ctx, `
			UPDATE payment_orders
			SET status = 'paid', paid_at = COALESCE(paid_at, now()), updated_at = now()
			WHERE id = $1
		`, orderID); err != nil {
			Error(w, http.StatusInternalServerError, "failed to complete test payment")
			return
		}
		if err := activateSubscriptionTx(ctx, tx, userIDFromContext(ctx), planCode, orderID); err != nil {
			Error(w, http.StatusInternalServerError, "failed to activate subscription")
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to commit test payment")
		return
	}
	JSON(w, http.StatusOK, map[string]any{
		"order_id":  orderID,
		"status":    "paid",
		"test_mode": true,
	})
}

func activateSubscriptionTx(ctx context.Context, tx pgx.Tx, userID, planCode, externalID string) error {
	plan, ok := paidSubscriptionPlans[planCode]
	if !ok {
		return fmt.Errorf("unknown plan %q", planCode)
	}
	var subscriptionID string
	err := tx.QueryRow(ctx, `
		UPDATE subscriptions
		SET plan_code = $2, platform = 'optima', status = 'active', external_id = $3,
		    current_period_end = now() + ($4::text || ' days')::interval, updated_at = now()
		WHERE user_id = $1 AND status IN ('active', 'trialing')
		RETURNING id::text
	`, userID, plan.Code, externalID, plan.PeriodDays).Scan(&subscriptionID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			INSERT INTO subscriptions
			    (user_id, plan_code, platform, status, external_id, current_period_end)
			VALUES ($1, $2, 'optima', 'active', $3, now() + ($4::text || ' days')::interval)
			RETURNING id::text
		`, userID, plan.Code, externalID, plan.PeriodDays).Scan(&subscriptionID)
	}
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO subscription_events (subscription_id, event_type, platform, payload_ref)
		VALUES ($1, 'payment_confirmed', 'optima', $2)
	`, subscriptionID, externalID)
	return err
}

// OptimaWebhook is deliberately fail-closed until the bank's signed payload
// contract is supplied. No unauthenticated callback can activate a subscription.
func OptimaWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	JSON(w, http.StatusNotImplemented, map[string]string{
		"error": "Optima webhook contract is not configured",
		"code":  "optima_webhook_not_configured",
	})
}

func renderOptimaPaymentURL(template string, order paymentOrderResponse) string {
	values := map[string]string{
		"order_id":    order.OrderID,
		"amount":      fmt.Sprintf("%.2f", order.Amount),
		"currency":    order.Currency,
		"return_url":  appState.PaymentReturnURL,
		"webhook_url": appState.PaymentWebhookURL,
	}
	result := template
	for key, value := range values {
		encoded := url.QueryEscape(value)
		result = strings.ReplaceAll(result, "{{"+key+"}}", encoded)
		result = strings.ReplaceAll(result, "{"+key+"}", encoded)
	}
	return result
}
