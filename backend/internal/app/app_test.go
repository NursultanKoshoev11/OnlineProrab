package app

import (
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
)

func TestAllowsNoSMSProviderOnlyForConfiguredStagingTestPhoneOrProductionReview(t *testing.T) {
	staging := config.Config{Env: config.StagingEnv}
	if allowsNoSMSProvider(staging) {
		t.Fatal("staging without a test phone and code must require an SMS provider")
	}

	staging.StagingTestSMSPhone = "+996700000001"
	staging.StagingTestSMSCode = "111111"
	if !allowsNoSMSProvider(staging) {
		t.Fatal("staging with an allowlisted test phone and code should not require SMS")
	}

	production := config.Config{Env: config.ProductionEnv, ReviewOnlyMode: true}
	if !allowsNoSMSProvider(production) {
		t.Fatal("production review-only mode should continue to allow no SMS provider")
	}

	production.ReviewOnlyMode = false
	if allowsNoSMSProvider(production) {
		t.Fatal("production without review-only mode must require an SMS provider")
	}
}
