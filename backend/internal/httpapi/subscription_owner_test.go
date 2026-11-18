package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProjectAccessFollowsTheOwnersSubscription(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db}
	ctx := context.Background()

	seedUser := func(phone, status, trialEnds string) string {
		var id string
		if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ($1) RETURNING id::text`, phone).Scan(&id); err != nil {
			t.Fatalf("seed user: %v", err)
		}
		if _, err := db.Pool.Exec(ctx, `
			INSERT INTO account_subscriptions (user_id, plan_code, status, started_at, trial_ends_at)
			VALUES ($1, 'trial', $2, now() - interval '40 days', now() + $3::interval)
		`, id, status, trialEnds); err != nil {
			t.Fatalf("seed subscription: %v", err)
		}
		return id
	}
	owner := seedUser("+996700000501", "trialing", "10 days")
	worker := seedUser("+996700000502", "expired", "-10 days")

	var projectID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO projects (owner_id, name) VALUES ($1, 'Объект') RETURNING id::text`, owner).Scan(&projectID); err != nil {
		t.Fatalf("seed project: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'owner'), ($1, $3, 'worker')
	`, projectID, owner, worker); err != nil {
		t.Fatalf("seed members: %v", err)
	}

	gate := func(userID string) int {
		request := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
		recorder := httptest.NewRecorder()
		if requireCurrentSubscription(recorder, request.WithContext(withUserID(request.Context(), userID)), userID) {
			return http.StatusNoContent
		}
		return recorder.Code
	}

	if code := gate(worker); code != http.StatusNoContent {
		t.Fatalf("worker with an expired own trial was blocked from the paid owner's project: %d", code)
	}
	if !canContributeToProject(ctx, worker, projectID) {
		t.Fatalf("worker lost project access although the owner's subscription is current")
	}

	if _, err := db.Pool.Exec(ctx, `UPDATE account_subscriptions SET status = 'expired' WHERE user_id = $1`, owner); err != nil {
		t.Fatalf("expire owner: %v", err)
	}
	if canAccessProject(ctx, worker, projectID) {
		t.Fatalf("worker kept access after the owner's subscription expired")
	}
	if code := gate(worker); code != http.StatusForbidden {
		t.Fatalf("worker without any paid project passed the subscription gate: %d", code)
	}
}

func TestSubscriptionExpiredErrorCarriesMachineReadableCode(t *testing.T) {
	recorder := httptest.NewRecorder()
	status, message, _ := subscriptionHTTPError(errSubscriptionExpired)
	Error(recorder, status, message)
	if body := recorder.Body.String(); !strings.Contains(body, `"code":"subscription_expired"`) {
		t.Fatalf("subscription expiry response has no stable code: %s", body)
	}
	other := httptest.NewRecorder()
	Error(other, http.StatusBadRequest, "invalid JSON body")
	if strings.Contains(other.Body.String(), `"code"`) {
		t.Fatalf("ordinary errors must not carry a code: %s", other.Body.String())
	}
}
