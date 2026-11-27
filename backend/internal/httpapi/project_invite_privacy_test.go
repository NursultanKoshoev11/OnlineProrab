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
	isMember := func() bool {
		t.Helper()
		var member bool
		if err := db.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2)`, projectID, registered).Scan(&member); err != nil {
			t.Fatalf("check membership: %v", err)
		}
		return member
	}
	if isMember() {
		t.Fatal("a registered account must not join a project before accepting the invitation")
	}

	// The invitee sees the invitation and joins only by accepting it.
	listRequest := httptest.NewRequest(http.MethodGet, "/api/v1/project-invites/incoming", nil)
	listRequest = listRequest.WithContext(withUserID(listRequest.Context(), registered))
	listRecorder := httptest.NewRecorder()
	IncomingProjectInvites(listRecorder, listRequest)
	var incoming struct {
		Items []incomingProjectInvite `json:"items"`
	}
	if err := json.Unmarshal(listRecorder.Body.Bytes(), &incoming); err != nil || listRecorder.Code != http.StatusOK || len(incoming.Items) != 1 || incoming.Items[0].ProjectID != projectID || incoming.Items[0].ProjectName != "Объект" {
		t.Fatalf("incoming invitations = %d %s (%v)", listRecorder.Code, listRecorder.Body.String(), err)
	}
	decide := func(handler http.HandlerFunc, userID, inviteID string) int {
		request := httptest.NewRequest(http.MethodPost, "/api/v1/project-invites/incoming/accept", strings.NewReader(`{"invite_id":"`+inviteID+`"}`))
		request = request.WithContext(withUserID(request.Context(), userID))
		recorder := httptest.NewRecorder()
		handler(recorder, request)
		return recorder.Code
	}
	if code := decide(AcceptIncomingProjectInvite, owner, incoming.Items[0].ID); code != http.StatusNotFound {
		t.Fatalf("another account accepting the invitation = %d, want 404", code)
	}
	if code := decide(AcceptIncomingProjectInvite, registered, incoming.Items[0].ID); code != http.StatusOK {
		t.Fatalf("accept invitation = %d, want 200", code)
	}
	if !isMember() {
		t.Fatal("accepting the invitation must add the account to the project")
	}
	if code := decide(DeclineIncomingProjectInvite, registered, incoming.Items[0].ID); code != http.StatusNotFound {
		t.Fatalf("declining an accepted invitation = %d, want 404", code)
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
