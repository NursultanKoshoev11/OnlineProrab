package httpapi

import "testing"

func TestRenderOptimaPaymentURL(t *testing.T) {
	oldReturnURL := appState.PaymentReturnURL
	oldWebhookURL := appState.PaymentWebhookURL
	defer func() {
		appState.PaymentReturnURL = oldReturnURL
		appState.PaymentWebhookURL = oldWebhookURL
	}()

	appState.PaymentReturnURL = "https://stroy.example/return?source=app"
	appState.PaymentWebhookURL = "https://stroy.example/webhook"
	got := renderOptimaPaymentURL(
		"https://bank.example/pay?order={order_id}&amount={amount}&currency={currency}&return={return_url}&hook={{webhook_url}}",
		paymentOrderResponse{
			OrderID:  "order-123",
			Amount:   990,
			Currency: "KGS",
		},
	)
	want := "https://bank.example/pay?order=order-123&amount=990.00&currency=KGS&return=https%3A%2F%2Fstroy.example%2Freturn%3Fsource%3Dapp&hook=https%3A%2F%2Fstroy.example%2Fwebhook"
	if got != want {
		t.Fatalf("unexpected payment URL: got %q want %q", got, want)
	}
}

func TestPaidSubscriptionPlansAreServerOwned(t *testing.T) {
	if paidSubscriptionPlans["pro"].AmountKGS != 990 {
		t.Fatal("pro price must remain server-owned at 990 KGS")
	}
	if paidSubscriptionPlans["business"].AmountKGS != 2990 {
		t.Fatal("business price must remain server-owned at 2990 KGS")
	}
}
