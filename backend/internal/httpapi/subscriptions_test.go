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
