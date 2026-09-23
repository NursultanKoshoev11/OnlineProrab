package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
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

func mustPlanPrice(plan subscriptionPlan, period string) int {
	price, err := planPrice(plan, period)
	if err != nil {
		panic(err)
	}
	return price
}
