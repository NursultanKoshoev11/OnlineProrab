package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProjectInviteDoesNotRevealWhetherPhoneIsRegistered(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db, IsProductionLike: true}
	ctx := context.Background()

	var owner, registered, projectID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000601') RETURNING id::text`).Scan(&owner); err != nil {
		t.Fatalf("seed owner: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO account_subscriptions (user_id, plan_code, status, billing_period, started_at, trial_ends_at, current_period_end)
		VALUES ($1, 'max', 'active', 'month', now() - interval '40 days', now() - interval '10 days', now() + interval '30 days')
	`, owner); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000602') RETURNING id::text`).Scan(&registered); err != nil {
		t.Fatalf("seed registered user: %v", err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO projects (owner_id, name) VALUES ($1, 'Объект') RETURNING id::text`, owner).Scan(&projectID); err != nil {
		t.Fatalf("seed project: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'owner')`, projectID, owner); err != nil {
		t.Fatalf("seed owner membership: %v", err)
	}

	invite := func(phone string) (int, string) {
		body := `{"project_id":"` + projectID + `","phone":"` + phone + `","role":"worker"}`
		request := httptest.NewRequest(http.MethodPost, "/api/v1/project-invites", strings.NewReader(body))
		request = request.WithContext(withUserID(request.Context(), owner))
		recorder := httptest.NewRecorder()
		CreateProjectInvite(recorder, request)
		return recorder.Code, recorder.Body.String()
	}

	registeredCode, registeredBody := invite("+996700000602")
	unknownCode, unknownBody := invite("+996700000603")
	if registeredCode != http.StatusCreated || unknownCode != http.StatusCreated {
		t.Fatalf("invite codes = %d / %d, want 201 for both: %s / %s", registeredCode, unknownCode, registeredBody, unknownBody)
	}
	if registeredBody != unknownBody {
		t.Fatalf("responses differ and reveal registration:\nregistered: %s\nunknown:    %s", registeredBody, unknownBody)
	}
	var decoded map[string]any
	if err := json.Unmarshal([]byte(registeredBody), &decoded); err != nil || decoded["status"] != "invited" {
		t.Fatalf("unexpected invite response %s (%v)", registeredBody, err)
	}
	for _, leaked := range []string{"user_id", "invite_token", "added"} {
		if strings.Contains(registeredBody, leaked) {
			t.Fatalf("production invite response leaks %q: %s", leaked, registeredBody)
		}
	}
	var isMember bool
	if err := db.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2)`, projectID, registered).Scan(&isMember); err != nil || !isMember {
		t.Fatalf("registered user was not added to the project (err=%v)", err)
	}

	// Fill the hourly allowance, then the next invitation must be refused.
	for i := 2; i < projectInviteRateLimit; i++ {
		if _, err := db.Pool.Exec(ctx, `INSERT INTO auth_attempts (remote_key, action) VALUES ($1, 'project_invite')`, "user:"+owner); err != nil {
			t.Fatalf("seed invite attempts: %v", err)
		}
	}
	if code, body := invite("+996700000604"); code != http.StatusTooManyRequests {
		t.Fatalf("invite over the hourly limit = %d %s, want 429", code, body)
	}
}
