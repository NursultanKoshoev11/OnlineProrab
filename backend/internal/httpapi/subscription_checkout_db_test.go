package httpapi

import (
	"context"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/payment/obank"
)

// openMigratedTestDB applies the real embedded migrations into a throwaway
// database so payment tests run against the production table definitions.
func openMigratedTestDB(t *testing.T) *database.DB {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	adminDB, err := database.Open(ctx, url)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	name := fmt.Sprintf("payment_test_%d_%d", os.Getpid(), time.Now().UnixNano())
	if _, err := adminDB.Pool.Exec(ctx, `CREATE DATABASE `+name); err != nil {
		adminDB.Close()
		t.Fatalf("create isolated database: %v", err)
	}
	poolConfig, err := pgxpool.ParseConfig(url)
	if err != nil {
		t.Fatalf("parse test database URL: %v", err)
	}
	poolConfig.ConnConfig.Database = name
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		t.Fatalf("create isolated pool: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		_, _ = adminDB.Pool.Exec(cleanupCtx, `DROP DATABASE IF EXISTS `+name+` WITH (FORCE)`)
		adminDB.Close()
	})
	db := &database.DB{Pool: pool}
	if err := db.ApplyMigrations(ctx); err != nil {
		t.Fatalf("apply migrations: %v", err)
	}
	return db
}

func TestOBankPaidResultActivatesLocallyCanceledOrder(t *testing.T) {
	db := openMigratedTestDB(t)
	previousState := appState
	defer func() { appState = previousState }()
	appState = State{DB: db}

	ctx := context.Background()
	var userID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000123') RETURNING id::text`).Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	const orderID = "order-canceled-then-paid"
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO subscription_payment_orders (
			order_id, user_id, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status, provider_invoice_id
		) VALUES ($1, $2, 'idem-key-0123456789', 'standard', 'month', 500, 50000, 'KGS', 'canceled', 'inv-1')
	`, orderID, userID); err != nil {
		t.Fatalf("seed canceled order: %v", err)
	}

	result := obank.Result{
		OrderID:       orderID,
		TransactionID: "txn-1",
		InvoiceID:     "inv-1",
		AmountKopecks: 50000,
		Currency:      "KGS",
		Status:        2,
	}
	// A late cancel notification is acknowledged without changes.
	if err := applyOBankResult(ctx, result); err != nil {
		t.Fatalf("late cancel result: %v", err)
	}

	result.Status = 3
	if err := applyOBankResult(ctx, result); err != nil {
		t.Fatalf("paid result for canceled order: %v", err)
	}
	// The bank retries callbacks; a duplicate must stay idempotent.
	if err := applyOBankResult(ctx, result); err != nil {
		t.Fatalf("duplicate paid result: %v", err)
	}

	var orderStatus, transactionID string
	if err := db.Pool.QueryRow(ctx, `
		SELECT status, COALESCE(provider_transaction_id, '') FROM subscription_payment_orders WHERE order_id = $1
	`, orderID).Scan(&orderStatus, &transactionID); err != nil {
		t.Fatalf("load order: %v", err)
	}
	if orderStatus != "paid" || transactionID != "txn-1" {
		t.Fatalf("order status=%q transaction=%q, want paid/txn-1", orderStatus, transactionID)
	}
	var planCode, subscriptionStatus string
	var periodEnd *time.Time
	if err := db.Pool.QueryRow(ctx, `
		SELECT plan_code, status, current_period_end FROM account_subscriptions WHERE user_id = $1
	`, userID).Scan(&planCode, &subscriptionStatus, &periodEnd); err != nil {
		t.Fatalf("load subscription: %v", err)
	}
	if planCode != "standard" || subscriptionStatus != "active" || periodEnd == nil || !periodEnd.After(time.Now()) {
		t.Fatalf("subscription plan=%q status=%q end=%v, want active standard", planCode, subscriptionStatus, periodEnd)
	}

	// A mismatched amount for the same order is still rejected.
	result.TransactionID = "txn-2"
	result.AmountKopecks = 1
	if err := applyOBankResult(ctx, result); err == nil {
		t.Fatalf("mismatched paid result was accepted")
	}
}

func TestConcurrentCheckoutsCreateOneOBankInvoice(t *testing.T) {
	db := openMigratedTestDB(t)
	previousState := appState
	previousCreate := createOBankInvoiceFunc
	defer func() {
		appState = previousState
		createOBankInvoiceFunc = previousCreate
	}()
	appState = State{DB: db}

	var calls atomic.Int32
	createOBankInvoiceFunc = func(ctx context.Context, order subscriptionPaymentOrder) (obank.Invoice, error) {
		n := calls.Add(1)
		// Keep the bank call slow enough that every request reaches the lock
		// while the first one is still waiting for the bank.
		time.Sleep(300 * time.Millisecond)
		return obank.Invoice{
			ID:         fmt.Sprintf("inv-%d", n),
			PaymentURL: fmt.Sprintf("https://pay.example/inv-%d", n),
		}, nil
	}

	ctx := context.Background()
	var userID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000124') RETURNING id::text`).Scan(&userID); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	order := subscriptionPaymentOrder{
		OrderID: "order-concurrent-checkout", UserID: userID, IdempotencyKey: "idem-key-concurrent-01",
		PlanID: "standard", BillingPeriod: "month", AmountKGS: 500, AmountKopecks: 50000,
		Currency: "KGS", Status: "pending",
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO subscription_payment_orders (
			order_id, user_id, idempotency_key, plan_code, billing_period,
			amount_kgs, amount_kopecks, currency, status
		) VALUES ($1, $2, $3, 'standard', 'month', 500, 50000, 'KGS', 'pending')
	`, order.OrderID, userID, order.IdempotencyKey); err != nil {
		t.Fatalf("seed order: %v", err)
	}

	const requests = 5
	results := make([]subscriptionPaymentOrder, requests)
	errs := make([]error, requests)
	var wg sync.WaitGroup
	for i := range requests {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i], errs[i] = ensureOBankInvoice(ctx, order)
		}()
	}
	wg.Wait()

	if got := calls.Load(); got != 1 {
		t.Fatalf("bank invoice created %d times, want exactly once", got)
	}
	for i := range requests {
		if errs[i] != nil {
			t.Fatalf("request %d: %v", i, errs[i])
		}
		if results[i].InvoiceID != "inv-1" || results[i].PaymentURL != "https://pay.example/inv-1" {
			t.Fatalf("request %d got invoice %q url %q, want the single saved invoice", i, results[i].InvoiceID, results[i].PaymentURL)
		}
	}
	var savedInvoice string
	if err := db.Pool.QueryRow(ctx, `SELECT provider_invoice_id FROM subscription_payment_orders WHERE order_id = $1`, order.OrderID).Scan(&savedInvoice); err != nil {
		t.Fatalf("load order: %v", err)
	}
	if savedInvoice != "inv-1" {
		t.Fatalf("saved invoice %q, want inv-1", savedInvoice)
	}
}
