package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
)

func TestSubscriptionReadEndpointsRejectMutatingMethods(t *testing.T) {
	for _, handler := range []http.HandlerFunc{ListPlans, SubscriptionStatus} {
		recorder := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/subscriptions", nil)
		handler(recorder, req)
		if recorder.Code != http.StatusMethodNotAllowed {
			t.Fatalf("expected 405 for %T, got %d", handler, recorder.Code)
		}
	}
}

func TestSubscriptionPlansMatchProductRules(t *testing.T) {
	expected := []struct {
		id, name                                            string
		price, annualDiscount, projects, invited, trialDays int
	}{
		{"trial", "Пробный период", 0, 0, 1, 0, 30},
		{"standard", "Стандартный", 3000, 10, 5, 5, 0},
		{"max", "Максимальный", 5000, 15, 20, 20, 0},
	}
	if len(subscriptionPlans) != len(expected) {
		t.Fatalf("expected %d plans, got %d", len(expected), len(subscriptionPlans))
	}
	for i, want := range expected {
		got := subscriptionPlans[i]
		if got.ID != want.id || got.Name != want.name || got.PriceKGS != want.price ||
			got.AnnualDiscountPercent != want.annualDiscount ||
			got.MaxProjects != want.projects || got.MaxInvitedMembers != want.invited ||
			got.TrialDays != want.trialDays {
			t.Fatalf("plan %d mismatch: got %#v, want %#v", i, got, want)
		}
	}
}

func TestSubscriptionAnnualPrices(t *testing.T) {
	standard, _ := planByCode("standard")
	maximum, _ := planByCode("max")

	if got, want := mustPlanPrice(standard, "year"), 32400; got != want {
		t.Fatalf("standard annual price: got %d, want %d", got, want)
	}
	if got, want := mustPlanPrice(maximum, "year"), 51000; got != want {
		t.Fatalf("max annual price: got %d, want %d", got, want)
	}
}

func TestStagingSandboxPriceOverrideIsDisplayedAndChargedOnlyInStaging(t *testing.T) {
	originalState := appState
	defer func() { appState = originalState }()
	appState = State{
		IsStaging:                  true,
		StagingTestPaymentPriceKGS: 10,
		OBank:                      config.OBankConfig{Enabled: true, Test: true},
	}

	standard, _ := planByCode("standard")
	if got, _ := planPrice(standard, "month"); got != 10 {
		t.Fatalf("staging monthly test price = %d, want 10", got)
	}
	if got, _ := planPrice(standard, "year"); got != 10 {
		t.Fatalf("staging annual test price = %d, want 10", got)
	}
	recorder := httptest.NewRecorder()
	ListPlans(recorder, httptest.NewRequest(http.MethodGet, "/api/v1/subscriptions/plans", nil))
	var response struct {
		Plans []map[string]any `json:"plans"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode plans response: %v", err)
	}
	foundStandard := false
	for _, plan := range response.Plans {
		if plan["id"] == "standard" && (plan["price_kgs"] != float64(10) || plan["annual_price_kgs"] != float64(10) || plan["annual_discount_percent"] != float64(0)) {
			t.Fatalf("staging plan did not show the 10 KGS test price: %#v", plan)
		}
		if plan["id"] == "standard" {
			foundStandard = true
		}
	}
	if !foundStandard {
		t.Fatal("staging plans response did not include the standard plan")
	}

	appState.IsStaging = false
	if got, _ := planPrice(standard, "month"); got != 3000 {
		t.Fatalf("non-staging monthly plan price = %d, want 3000", got)
	}
}

func TestOperatorPriceOverrideAppliesToAllPaidPeriods(t *testing.T) {
	originalState := appState
	defer func() { appState = originalState }()
	appState = State{SubscriptionPriceOverrideKGS: 10}

	for _, planID := range []string{"standard", "max"} {
		plan, _ := planByCode(planID)
		for _, period := range []string{"month", "year"} {
			if got, _ := planPrice(plan, period); got != 10 {
				t.Fatalf("%s %s override price = %d, want 10", planID, period, got)
			}
		}
	}
}

func mustPlanPrice(plan subscriptionPlan, period string) int {
	price, err := planPrice(plan, period)
	if err != nil {
		panic(err)
	}
	return price
}
