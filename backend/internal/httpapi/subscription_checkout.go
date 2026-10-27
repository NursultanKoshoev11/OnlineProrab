package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/payment/obank"
	"github.com/jackc/pgx/v5"
)

const (
	maxCheckoutBodyBytes = 4 * 1024
	maxResultBodyBytes   = 64 * 1024
)

var (
	errCheckoutExists = errors.New("an open checkout already exists for another plan")
	errCheckoutState  = errors.New("checkout is no longer payable")
	errPaymentMissing = errors.New("payment order not found")
	errPaymentInvalid = errors.New("payment result does not match order")
)

type subscriptionCheckoutRequest struct {
	PlanID         string `json:"plan_id"`
	BillingPeriod  string `json:"billing_period"`
	IdempotencyKey string `json:"idempotency_key"`
}

type subscriptionPaymentOrder struct {
	OrderID             string
	UserID              string
	IdempotencyKey      string
	PlanID              string
	BillingPeriod       string
	AmountKGS           int
	AmountKopecks       int64
	Currency            string
	Status              string
	InvoiceID           string
	ProviderTransaction string
	PaymentURL          string
	BankAppLink         string
	CreatedAt           time.Time
	PaidAt              *time.Time
}

type checkoutResponse struct {
	OrderID       string `json:"order_id"`
	Status        string `json:"status"`
	PlanID        string `json:"plan_id"`
	BillingPeriod string `json:"billing_period"`
	AmountKGS     int    `json:"amount_kgs"`
	Currency      string `json:"currency"`
	PaymentURL    string `json:"payment_url,omitempty"`
	AppLink       string `json:"app_link,omitempty"`
	CreatedAt     string `json:"created_at,omitempty"`
	PaidAt        string `json:"paid_at,omitempty"`
}

func SubscriptionCheckout(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		getSubscriptionCheckout(w, r)
		return
	}
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !appState.OBank.Enabled {
		Error(w, http.StatusServiceUnavailable, "O!Dengi checkout is not configured")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxCheckoutBodyBytes)
	var request subscriptionCheckoutRequest
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		Error(w, http.StatusBadRequest, "invalid checkout request")
		return
	}
	request.PlanID = strings.TrimSpace(request.PlanID)
	request.BillingPeriod = strings.TrimSpace(request.BillingPeriod)
	request.IdempotencyKey = strings.TrimSpace(request.IdempotencyKey)
	if len(request.IdempotencyKey) < 16 || len(request.IdempotencyKey) > 64 || !safeIdempotencyKey(request.IdempotencyKey) {
		Error(w, http.StatusBadRequest, "invalid idempotency key")
		return
	}
	plan, err := planByCode(request.PlanID)
	if err != nil || plan.ID == "trial" {
		Error(w, http.StatusBadRequest, "select a paid subscription plan")
		return
	}
	priceKGS, err := planPrice(plan, request.BillingPeriod)
	if err != nil || priceKGS <= 0 || int64(priceKGS) > math.MaxInt64/100 {
		Error(w, http.StatusBadRequest, "invalid subscription price")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	order, err := reserveSubscriptionCheckout(ctx, userIDFromContext(r.Context()), request, priceKGS)
	if err != nil {
		switch {
		case errors.Is(err, errCheckoutExists):
			Error(w, http.StatusConflict, "finish or wait for the existing payment before selecting another plan")
		case errors.Is(err, errCheckoutState):
			Error(w, http.StatusConflict, "this checkout is no longer payable; start a new checkout")
		default:
			log.Printf("subscription checkout reservation failed: %v", err)
			Error(w, http.StatusInternalServerError, "could not start checkout")
		}
		return
	}
	if order.Status == "paid" {
		writeCheckoutResponse(w, http.StatusOK, order)
		return
	}
	if order.Status == "canceled" {
		Error(w, http.StatusConflict, "this checkout was canceled; start a new checkout")
		return
	}
	if order.PaymentURL == "" {
		invoice, err := createOBankInvoice(r.Context(), order)
		if err != nil {
			log.Printf("O!Dengi invoice creation failed order_id=%s: %v", order.OrderID, err)
			Error(w, http.StatusBadGateway, "the bank could not create a payment invoice; retry this checkout")
			return
		}
		ctx, cancel = context.WithTimeout(r.Context(), 3*time.Second)
		err = saveOBankInvoice(ctx, order.OrderID, invoice)
		cancel()
		if err != nil {
			log.Printf("O!Dengi invoice save failed order_id=%s: %v", order.OrderID, err)
			Error(w, http.StatusServiceUnavailable, "the payment invoice could not be saved")
			return
		}
		order.InvoiceID = invoice.ID
		order.PaymentURL = invoice.PaymentURL
		order.BankAppLink = invoice.AppLink
	}
	writeCheckoutResponse(w, http.StatusCreated, order)
}

func getSubscriptionCheckout(w http.ResponseWriter, r *http.Request) {
	if !appState.OBank.Enabled {
		Error(w, http.StatusServiceUnavailable, "O!Dengi checkout is not configured")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	orderID := strings.TrimSpace(r.URL.Query().Get("order_id"))
	if orderID == "" || len(orderID) > 64 {
		Error(w, http.StatusBadRequest, "invalid order ID")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	order, err := loadSubscriptionPaymentOrder(ctx, userIDFromContext(r.Context()), orderID)
	cancel()
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			Error(w, http.StatusNotFound, "payment order not found")
		} else {
			Error(w, http.StatusServiceUnavailable, "could not load payment status")
		}
		return
	}

	if (order.Status == "pending" || order.Status == "processing") && order.InvoiceID != "" && claimOBankStatusCheck(r.Context(), order.OrderID) {
		status, statusErr := obank.GetStatus(r.Context(), appState.OBank, order.InvoiceID, order.OrderID)
		if statusErr == nil {
			switch status.Status {
			case "approved":
				if status.AmountKopecks == order.AmountKopecks && status.TransactionID != "" {
					if err := markSubscriptionPaymentPaid(r.Context(), order.OrderID, status.TransactionID, status.AmountKopecks, order.InvoiceID); err == nil {
						order.Status = "paid"
					} else {
						log.Printf("O!Dengi status reconciliation failed order_id=%s: %v", order.OrderID, err)
					}
				} else {
					log.Printf("O!Dengi approved payment mismatch order_id=%s", order.OrderID)
				}
			case "processing":
				order.Status = "processing"
				_ = updateSubscriptionPaymentStatus(r.Context(), order.OrderID, "processing")
			case "canceled", "cancelled":
				order.Status = "canceled"
				_ = updateSubscriptionPaymentStatus(r.Context(), order.OrderID, "canceled")
			}
		}
	}

	ctx, cancel = context.WithTimeout(r.Context(), 3*time.Second)
	order, err = loadSubscriptionPaymentOrder(ctx, userIDFromContext(r.Context()), orderID)
	cancel()
	if err != nil {
		Error(w, http.StatusServiceUnavailable, "could not load payment status")
		return
	}
	writeCheckoutResponse(w, http.StatusOK, order)
}

func claimOBankStatusCheck(ctx context.Context, orderID string) bool {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	commandTag, err := appState.DB.Pool.Exec(ctx, `
		UPDATE subscription_payment_orders
		SET status_checked_at = now()
		WHERE order_id = $1
		  AND status IN ('pending', 'processing')
		  AND (status_checked_at IS NULL OR status_checked_at < now() - interval '5 seconds')
	`, orderID)
	return err == nil && commandTag.RowsAffected() == 1
}

func OBankResult(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !appState.OBank.Enabled || appState.OBank.Password == "" {
		Error(w, http.StatusServiceUnavailable, "O!Dengi result processing is not configured")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxResultBodyBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		Error(w, http.StatusBadRequest, "invalid O!Dengi result payload")
		return
	}
	result, err := obank.VerifyResult(body, appState.OBank.Password)
	if err != nil {
		Error(w, http.StatusUnauthorized, "invalid O!Dengi result")
		return
	}
	if result.SiteID != appState.OBank.SID || result.Test != configuredOBankTestFlag() {
		Error(w, http.StatusUnauthorized, "O!Dengi result does not match merchant configuration")
		return
	}
	if err := applyOBankResult(r.Context(), result); err != nil {
		if errors.Is(err, errPaymentMissing) {
			Error(w, http.StatusNotFound, "payment order not found")
			return
		}
		if errors.Is(err, errPaymentInvalid) {
			Error(w, http.StatusUnprocessableEntity, "O!Dengi result does not match payment order")
			return
		}
		log.Printf("O!Dengi result processing failed order_id=%s: %v", result.OrderID, err)
		Error(w, http.StatusServiceUnavailable, "could not process O!Dengi result")
		return
	}
	JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func reserveSubscriptionCheckout(ctx context.Context, userID string, request subscriptionCheckoutRequest, priceKGS int) (subscriptionPaymentOrder, error) {
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		return subscriptionPaymentOrder{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := ensureSubscription(ctx, tx, userID, true); err != nil {
		return subscriptionPaymentOrder{}, err
	}

	order, err := findSubscriptionPaymentByIdempotency(ctx, tx, userID, request.IdempotencyKey)
	if err == nil {
		if order.PlanID != request.PlanID || order.BillingPeriod != request.BillingPeriod || order.AmountKGS != priceKGS {
			return subscriptionPaymentOrder{}, errCheckoutState
		}
		if order.Status == "canceled" || (order.Status != "paid" && order.CreatedAt.Before(time.Now().UTC().Add(-24*time.Hour))) {
			return order, errCheckoutState
		}
		if err := tx.Commit(ctx); err != nil {
			return subscriptionPaymentOrder{}, err
		}
		return order, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return subscriptionPaymentOrder{}, err
	}

	order, err = findOpenSubscriptionPayment(ctx, tx, userID)
	if err == nil {
		if order.PlanID != request.PlanID || order.BillingPeriod != request.BillingPeriod || order.AmountKGS != priceKGS {
			return subscriptionPaymentOrder{}, errCheckoutExists
		}
		if err := tx.Commit(ctx); err != nil {
			return subscriptionPaymentOrder{}, err
		}
		return order, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return subscriptionPaymentOrder{}, err
	}

	orderID, err := newOBankOrderID()
	if err != nil {
		return subscriptionPaymentOrder{}, err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO subscription_payment_orders (
			order_id, user_id, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status
		) VALUES ($1, $2, $3, $4, $5, $6, $7, 'KGS', 'pending')
	`, orderID, userID, request.IdempotencyKey, request.PlanID, request.BillingPeriod, priceKGS, int64(priceKGS)*100)
	if err != nil {
		return subscriptionPaymentOrder{}, err
	}
	order = subscriptionPaymentOrder{
		OrderID:        orderID,
		UserID:         userID,
		IdempotencyKey: request.IdempotencyKey,
		PlanID:         request.PlanID,
		BillingPeriod:  request.BillingPeriod,
		AmountKGS:      priceKGS,
		AmountKopecks:  int64(priceKGS) * 100,
		Currency:       "KGS",
		Status:         "pending",
		CreatedAt:      time.Now().UTC(),
	}
	if err := tx.Commit(ctx); err != nil {
		return subscriptionPaymentOrder{}, err
	}
	return order, nil
}

type subscriptionPaymentQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func findSubscriptionPaymentByIdempotency(ctx context.Context, db subscriptionPaymentQuerier, userID, key string) (subscriptionPaymentOrder, error) {
	return scanSubscriptionPayment(db.QueryRow(ctx, `
		SELECT order_id, user_id::text, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status,
			COALESCE(provider_invoice_id, ''), COALESCE(provider_transaction_id, ''),
			COALESCE(payment_url, ''), COALESCE(bank_app_link, ''), created_at, paid_at
		FROM subscription_payment_orders
		WHERE user_id = $1 AND idempotency_key = $2
	`, userID, key))
}

func findOpenSubscriptionPayment(ctx context.Context, db subscriptionPaymentQuerier, userID string) (subscriptionPaymentOrder, error) {
	return scanSubscriptionPayment(db.QueryRow(ctx, `
		SELECT order_id, user_id::text, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status,
			COALESCE(provider_invoice_id, ''), COALESCE(provider_transaction_id, ''),
			COALESCE(payment_url, ''), COALESCE(bank_app_link, ''), created_at, paid_at
		FROM subscription_payment_orders
		WHERE user_id = $1 AND status IN ('pending', 'processing')
		  AND created_at > now() - interval '24 hours'
		ORDER BY created_at DESC
		LIMIT 1
		FOR UPDATE
	`, userID))
}

func loadSubscriptionPaymentOrder(ctx context.Context, userID, orderID string) (subscriptionPaymentOrder, error) {
	return scanSubscriptionPayment(appState.DB.Pool.QueryRow(ctx, `
		SELECT order_id, user_id::text, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status,
			COALESCE(provider_invoice_id, ''), COALESCE(provider_transaction_id, ''),
			COALESCE(payment_url, ''), COALESCE(bank_app_link, ''), created_at, paid_at
		FROM subscription_payment_orders
		WHERE user_id = $1 AND order_id = $2
	`, userID, orderID))
}

func scanSubscriptionPayment(row pgx.Row) (subscriptionPaymentOrder, error) {
	var order subscriptionPaymentOrder
	err := row.Scan(
		&order.OrderID,
		&order.UserID,
		&order.IdempotencyKey,
		&order.PlanID,
		&order.BillingPeriod,
		&order.AmountKGS,
		&order.AmountKopecks,
		&order.Currency,
		&order.Status,
		&order.InvoiceID,
		&order.ProviderTransaction,
		&order.PaymentURL,
		&order.BankAppLink,
		&order.CreatedAt,
		&order.PaidAt,
	)
	return order, err
}

func createOBankInvoice(ctx context.Context, order subscriptionPaymentOrder) (obank.Invoice, error) {
	plan, err := planByCode(order.PlanID)
	if err != nil {
		return obank.Invoice{}, err
	}
	description := fmt.Sprintf("STROY: %s, %s", plan.Name, billingPeriodRussian(order.BillingPeriod))
	dateLife := time.Now().UTC().Add(24 * time.Hour).In(time.FixedZone("Kyrgyzstan", 6*60*60)).Format("2006-01-02 15:04:05")
	successURL, err := checkoutReturnURL(appState.OBank.ReturnURL, order.OrderID, "success")
	if err != nil {
		return obank.Invoice{}, err
	}
	failURL, err := checkoutReturnURL(appState.OBank.ReturnURL, order.OrderID, "failed")
	if err != nil {
		return obank.Invoice{}, err
	}
	return obank.CreateInvoice(ctx, appState.OBank, obank.CreateInvoiceData{
		OrderID:     order.OrderID,
		Description: description,
		Amount:      order.AmountKopecks,
		Currency:    order.Currency,
		Test:        configuredOBankTestFlag(),
		LongTerm:    0,
		DateLife:    &dateLife,
		SendPush:    0,
		SendSMS:     0,
		SuccessURL:  successURL,
		FailURL:     failURL,
		ResultURL:   appState.OBank.ResultURL,
	})
}

func saveOBankInvoice(ctx context.Context, orderID string, invoice obank.Invoice) error {
	commandTag, err := appState.DB.Pool.Exec(ctx, `
		UPDATE subscription_payment_orders
		SET provider_invoice_id = $2, payment_url = $3, bank_app_link = $4, updated_at = now()
		WHERE order_id = $1 AND status IN ('pending', 'processing')
	`, orderID, invoice.ID, invoice.PaymentURL, invoice.AppLink)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return errCheckoutState
	}
	return nil
}

func applyOBankResult(ctx context.Context, result obank.Result) error {
	if result.OrderID == "" || result.TransactionID == "" || result.AmountKopecks <= 0 || result.Currency != "KGS" {
		return errPaymentInvalid
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	order, err := scanSubscriptionPayment(tx.QueryRow(ctx, `
		SELECT order_id, user_id::text, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status,
			COALESCE(provider_invoice_id, ''), COALESCE(provider_transaction_id, ''),
			COALESCE(payment_url, ''), COALESCE(bank_app_link, ''), created_at, paid_at
		FROM subscription_payment_orders
		WHERE order_id = $1
		FOR UPDATE
	`, result.OrderID))
	if errors.Is(err, pgx.ErrNoRows) {
		return errPaymentMissing
	}
	if err != nil {
		return err
	}
	if result.AmountKopecks != order.AmountKopecks || result.Currency != order.Currency ||
		(result.InvoiceID != "" && order.InvoiceID != "" && result.InvoiceID != order.InvoiceID) {
		return errPaymentInvalid
	}
	if order.ProviderTransaction != "" && order.ProviderTransaction != result.TransactionID {
		return errPaymentInvalid
	}
	if order.Status == "paid" {
		return tx.Commit(ctx)
	}
	if order.Status == "canceled" && result.Status != 2 {
		return errCheckoutState
	}

	switch result.Status {
	case 1:
		_, err = tx.Exec(ctx, `
			UPDATE subscription_payment_orders
			SET status = 'processing',
			    provider_invoice_id = COALESCE(NULLIF(provider_invoice_id, ''), NULLIF($2, '')),
			    provider_transaction_id = COALESCE(NULLIF(provider_transaction_id, ''), NULLIF($3, '')),
			    updated_at = now()
			WHERE order_id = $1
		`, result.OrderID, result.InvoiceID, result.TransactionID)
	case 2:
		_, err = tx.Exec(ctx, `
			UPDATE subscription_payment_orders
			SET status = 'canceled',
			    provider_invoice_id = COALESCE(NULLIF(provider_invoice_id, ''), NULLIF($2, '')),
			    provider_transaction_id = COALESCE(NULLIF(provider_transaction_id, ''), NULLIF($3, '')),
			    updated_at = now()
			WHERE order_id = $1
		`, result.OrderID, result.InvoiceID, result.TransactionID)
	case 3:
		err = activateSubscriptionFromPayment(ctx, tx, order, result.TransactionID, result.InvoiceID)
	default:
		return errPaymentInvalid
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func markSubscriptionPaymentPaid(ctx context.Context, orderID, transactionID string, amountKopecks int64, invoiceID string) error {
	result := obank.Result{
		OrderID:       orderID,
		TransactionID: transactionID,
		AmountKopecks: amountKopecks,
		Currency:      "KGS",
		Status:        3,
		SiteID:        appState.OBank.SID,
		Test:          configuredOBankTestFlag(),
		InvoiceID:     invoiceID,
	}
	return applyOBankResult(ctx, result)
}

func activateSubscriptionFromPayment(ctx context.Context, tx pgx.Tx, order subscriptionPaymentOrder, transactionID, invoiceID string) error {
	state, err := ensureSubscription(ctx, tx, order.UserID, true)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	periodStart := now
	if state.Status == "active" && state.CurrentPeriodEnd != nil && state.CurrentPeriodEnd.After(now) {
		periodStart = *state.CurrentPeriodEnd
	}
	periodEnd := addSubscriptionPeriod(periodStart, order.BillingPeriod)
	if _, err := tx.Exec(ctx, `
		UPDATE account_subscriptions
		SET plan_code = $2,
		    status = 'active',
		    billing_period = $3,
		    started_at = $4,
		    current_period_end = $5,
		    updated_at = now()
		WHERE user_id = $1
	`, order.UserID, order.PlanID, order.BillingPeriod, periodStart, periodEnd); err != nil {
		return err
	}
	commandTag, err := tx.Exec(ctx, `
		UPDATE subscription_payment_orders
		SET status = 'paid',
		    provider_invoice_id = COALESCE(NULLIF(provider_invoice_id, ''), NULLIF($2, '')),
		    provider_transaction_id = $3,
		    paid_at = now(),
		    updated_at = now()
		WHERE order_id = $1 AND status IN ('pending', 'processing')
	`, order.OrderID, invoiceID, transactionID)
	if err != nil {
		return err
	}
	if commandTag.RowsAffected() != 1 {
		return errCheckoutState
	}
	return nil
}

func updateSubscriptionPaymentStatus(ctx context.Context, orderID, status string) error {
	if status != "processing" && status != "canceled" {
		return errCheckoutState
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	_, err := appState.DB.Pool.Exec(ctx, `
		UPDATE subscription_payment_orders
		SET status = $2, updated_at = now()
		WHERE order_id = $1 AND status IN ('pending', 'processing')
	`, orderID, status)
	return err
}

func writeCheckoutResponse(w http.ResponseWriter, status int, order subscriptionPaymentOrder) {
	response := checkoutResponse{
		OrderID:       order.OrderID,
		Status:        order.Status,
		PlanID:        order.PlanID,
		BillingPeriod: order.BillingPeriod,
		AmountKGS:     order.AmountKGS,
		Currency:      order.Currency,
		PaymentURL:    order.PaymentURL,
		CreatedAt:     order.CreatedAt.UTC().Format(time.RFC3339),
	}
	if order.Status == "pending" || order.Status == "processing" {
		response.AppLink = order.BankAppLink
	}
	if order.PaidAt != nil {
		response.PaidAt = order.PaidAt.UTC().Format(time.RFC3339)
	}
	JSON(w, status, response)
}

func checkoutReturnURL(base, orderID, result string) (string, error) {
	parsed, err := url.Parse(base)
	if err != nil {
		return "", err
	}
	query := parsed.Query()
	query.Set("order_id", orderID)
	query.Set("payment_result", result)
	if appState.IsStaging {
		query.Set("stage", "1")
	}
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func newOBankOrderID() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return "stroy_" + hex.EncodeToString(bytes), nil
}

func safeIdempotencyKey(value string) bool {
	for _, char := range value {
		if char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || char == '-' || char == '_' {
			continue
		}
		return false
	}
	return true
}

func billingPeriodRussian(period string) string {
	if period == "year" {
		return "1 год"
	}
	return "1 месяц"
}

func configuredOBankTestFlag() int {
	if appState.OBank.Test {
		return 1
	}
	return 0
}

func addSubscriptionPeriod(start time.Time, period string) time.Time {
	year, month, day := start.Date()
	if period == "year" {
		targetYear := year + 1
		lastDay := time.Date(targetYear, month+1, 0, 0, 0, 0, 0, start.Location()).Day()
		if day > lastDay {
			day = lastDay
		}
		return time.Date(targetYear, month, day, start.Hour(), start.Minute(), start.Second(), start.Nanosecond(), start.Location())
	}
	targetMonth := month + 1
	targetYear := year
	if targetMonth > 12 {
		targetMonth = time.January
		targetYear++
	}
	lastDay := time.Date(targetYear, targetMonth+1, 0, 0, 0, 0, 0, start.Location()).Day()
	if day > lastDay {
		day = lastDay
	}
	return time.Date(targetYear, targetMonth, day, start.Hour(), start.Minute(), start.Second(), start.Nanosecond(), start.Location())
}
