package httpapi

import (
	"context"
	"fmt"
	"os"
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
