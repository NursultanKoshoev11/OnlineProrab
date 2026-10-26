package httpapi

import (
	"net/url"
	"testing"
)

func TestCheckoutReturnURLUsesStagingAPISelectorOnlyInStaging(t *testing.T) {
	oldState := appState
	defer func() { appState = oldState }()

	appState.IsStaging = true
	stagingURL, err := checkoutReturnURL("https://stroy.com.kg/billing/", "order-123", "success")
	if err != nil {
		t.Fatalf("checkoutReturnURL staging: %v", err)
	}
	parsed, err := url.Parse(stagingURL)
	if err != nil {
		t.Fatalf("parse staging URL: %v", err)
	}
	if parsed.Query().Get("stage") != "1" || parsed.Query().Get("order_id") != "order-123" {
		t.Fatalf("staging return must select staging API and preserve order ID, got %q", stagingURL)
	}

	appState.IsStaging = false
	productionURL, err := checkoutReturnURL("https://stroy.com.kg/billing/", "order-456", "success")
	if err != nil {
		t.Fatalf("checkoutReturnURL production: %v", err)
	}
	parsed, err = url.Parse(productionURL)
	if err != nil {
		t.Fatalf("parse production URL: %v", err)
	}
	if parsed.Query().Has("stage") || parsed.Query().Get("order_id") != "order-456" {
		t.Fatalf("production return must not select staging API, got %q", productionURL)
	}
}
