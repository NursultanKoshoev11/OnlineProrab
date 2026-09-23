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
		id, name                            string
		price, projects, invited, trialDays int
	}{
		{"trial", "Пробный период", 0, 1, 0, 30},
		{"standard", "Стандартный", 3000, 5, 5, 0},
		{"max", "Максимальный", 5000, 20, 20, 0},
	}
	if len(subscriptionPlans) != len(expected) {
		t.Fatalf("expected %d plans, got %d", len(expected), len(subscriptionPlans))
	}
	for i, want := range expected {
		got := subscriptionPlans[i]
		if got.ID != want.id || got.Name != want.name || got.PriceKGS != want.price ||
			got.MaxProjects != want.projects || got.MaxInvitedMembers != want.invited ||
			got.TrialDays != want.trialDays {
			t.Fatalf("plan %d mismatch: got %#v, want %#v", i, got, want)
		}
	}
}
