package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

type testDeletionJournal struct {
	accountIDs []string
	objectKeys []string
	err        error
}

func (j *testDeletionJournal) RecordAccountDeletion(_ context.Context, userID string) error {
	j.accountIDs = append(j.accountIDs, userID)
	return j.err
}

func (j *testDeletionJournal) RecordObjectDeletion(_ context.Context, key string) error {
	j.objectKeys = append(j.objectKeys, key)
	return j.err
}

func TestDeleteAccountWritesExternalTombstoneBeforeCommit(t *testing.T) {
	db := openSMSAuthTestDB(t)
	createAccountDeletionFilesTable(t, db)
	oldState := appState
	defer func() { appState = oldState }()
	journal := &testDeletionJournal{}
	appState = State{DB: db, IsProductionLike: true, DeletionJournal: journal}

	userID := seedAccountDeletionUser(t, db)
	request := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	request = request.WithContext(withUserID(request.Context(), userID))
	response := httptest.NewRecorder()

	DeleteAccount(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected account deletion to succeed, got %d: %s", response.Code, response.Body.String())
	}
	if len(journal.accountIDs) != 1 || journal.accountIDs[0] != userID {
		t.Fatalf("expected one external tombstone for %s, got %v", userID, journal.accountIDs)
	}
	assertAccountDeletionRows(t, db, userID, 0, 0)
}

func TestDeleteAccountImmediatelyRevokesAccessToken(t *testing.T) {
	db := openSMSAuthTestDB(t)
	createAccountDeletionFilesTable(t, db)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{
		DB:               db,
		JWTSecret:        "account-deletion-test-signing-key-1234567890",
		AccessTokenTTL:   time.Hour,
		IsProductionLike: true,
		DeletionJournal:  &testDeletionJournal{},
	}

	userID := seedAccountDeletionUser(t, db)
	var sessionID string
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO refresh_sessions (user_id, token_hash, expires_at)
		VALUES ($1, 'account-deletion-access-test', now() + interval '1 day')
		RETURNING id::text
	`, userID).Scan(&sessionID); err != nil {
		t.Fatalf("create refresh session: %v", err)
	}
	token, err := signSessionAccessToken(userID, sessionID)
	if err != nil {
		t.Fatalf("sign access token: %v", err)
	}

	deleteRequest := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	deleteRequest = deleteRequest.WithContext(withUserID(deleteRequest.Context(), userID))
	deleteResponse := httptest.NewRecorder()
	DeleteAccount(deleteResponse, deleteRequest)
	if deleteResponse.Code != http.StatusOK {
		t.Fatalf("expected account deletion to succeed, got %d: %s", deleteResponse.Code, deleteResponse.Body.String())
	}

	handlerReached := false
	protectedHandler := requireAuth(func(w http.ResponseWriter, _ *http.Request) {
		handlerReached = true
		w.WriteHeader(http.StatusNoContent)
	})
	request := httptest.NewRequest(http.MethodGet, "/api/v1/projects", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	protectedHandler(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected a deleted account's token to be rejected, got %d: %s", response.Code, response.Body.String())
	}
	if handlerReached {
		t.Fatal("protected handler ran with a token for a deleted account")
	}
}

func TestDeleteAccountRollsBackWhenExternalTombstoneCannotBeWritten(t *testing.T) {
	db := openSMSAuthTestDB(t)
	createAccountDeletionFilesTable(t, db)
	oldState := appState
	defer func() { appState = oldState }()
	journal := &testDeletionJournal{err: errors.New("ledger unavailable")}
	appState = State{DB: db, IsProductionLike: true, DeletionJournal: journal}

	userID := seedAccountDeletionUser(t, db)
	request := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	request = request.WithContext(withUserID(request.Context(), userID))
	response := httptest.NewRecorder()

	DeleteAccount(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected unavailable ledger to block deletion, got %d: %s", response.Code, response.Body.String())
	}
	if len(journal.accountIDs) != 1 || journal.accountIDs[0] != userID {
		t.Fatalf("expected the deletion intent to be attempted, got %v", journal.accountIDs)
	}
	assertAccountDeletionRows(t, db, userID, 1, 1)
}

func TestDeleteAccountFailsClosedWithoutJournalInProduction(t *testing.T) {
	db := openSMSAuthTestDB(t)
	createAccountDeletionFilesTable(t, db)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db, IsProductionLike: true}
	userID := seedAccountDeletionUser(t, db)
	request := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	request = request.WithContext(withUserID(request.Context(), userID))
	response := httptest.NewRecorder()

	DeleteAccount(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected missing deletion journal to fail closed, got %d: %s", response.Code, response.Body.String())
	}
	assertAccountDeletionRows(t, db, userID, 1, 1)
}

func createAccountDeletionFilesTable(t *testing.T, db *database.DB) {
	t.Helper()
	if _, err := db.Pool.Exec(context.Background(), `
		CREATE TABLE files (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
			storage_path TEXT NOT NULL
		)
	`); err != nil {
		t.Fatalf("create isolated file table: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		CREATE TABLE projects (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			deleted_at TIMESTAMPTZ,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);
		CREATE TABLE project_members (
			project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
			user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
			PRIMARY KEY (project_id, user_id)
		)
	`); err != nil {
		t.Fatalf("create isolated project tables: %v", err)
	}
}

func seedAccountDeletionUser(t *testing.T, db *database.DB) string {
	t.Helper()
	var userID string
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO users (phone) VALUES ('+996700000299') RETURNING id::text
	`).Scan(&userID); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	if _, err := db.Pool.Exec(context.Background(), `
		INSERT INTO files (uploaded_by, storage_path) VALUES ($1, $2)
	`, userID, "project/2026/receipt.pdf"); err != nil {
		t.Fatalf("seed account upload: %v", err)
	}
	return userID
}

func assertAccountDeletionRows(t *testing.T, db *database.DB, userID string, wantUsers, wantFiles int) {
	t.Helper()
	var users, files int
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM users WHERE id = $1`, userID).Scan(&users); err != nil {
		t.Fatalf("count account after deletion: %v", err)
	}
	if err := db.Pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM files WHERE uploaded_by = $1`, userID).Scan(&files); err != nil {
		t.Fatalf("count account files after deletion: %v", err)
	}
	if users != wantUsers || files != wantFiles {
		t.Fatalf("unexpected deletion state: users=%d files=%d, want users=%d files=%d", users, files, wantUsers, wantFiles)
	}
}

func TestDeleteAccountHandsSharedProjectsToTheirTeam(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	appState = State{DB: db}
	ctx := context.Background()

	seedUser := func(phone string) string {
		var id string
		if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ($1) RETURNING id::text`, phone).Scan(&id); err != nil {
			t.Fatalf("seed user %s: %v", phone, err)
		}
		return id
	}
	seedProject := func(ownerID string, members map[string]string) string {
		var id string
		if err := db.Pool.QueryRow(ctx, `INSERT INTO projects (owner_id, name) VALUES ($1, 'Объект') RETURNING id::text`, ownerID).Scan(&id); err != nil {
			t.Fatalf("seed project: %v", err)
		}
		if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'owner')`, id, ownerID); err != nil {
			t.Fatalf("seed owner membership: %v", err)
		}
		for userID, role := range members {
			if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role, created_at) VALUES ($1, $2, $3, now() - interval '1 day')`, id, userID, role); err != nil {
				t.Fatalf("seed member: %v", err)
			}
		}
		return id
	}

	owner := seedUser("+996700000401")
	manager := seedUser("+996700000402")
	worker := seedUser("+996700000403")
	viewer := seedUser("+996700000404")
	sharedWithManager := seedProject(owner, map[string]string{worker: "worker", manager: "manager"})
	sharedWithViewer := seedProject(owner, map[string]string{viewer: "viewer"})
	solo := seedProject(owner, nil)
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO cost_items (project_id, created_by, title, amount, currency, spent_at)
		VALUES ($1, $2, 'Цемент', 1000, 'KGS', now())
	`, sharedWithManager, owner); err != nil {
		t.Fatalf("seed cost item: %v", err)
	}

	request := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
	request = request.WithContext(withUserID(request.Context(), owner))
	response := httptest.NewRecorder()
	DeleteAccount(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("delete account: %d %s", response.Code, response.Body.String())
	}

	assertOwner := func(projectID, wantOwner string) {
		t.Helper()
		var ownerID, role string
		if err := db.Pool.QueryRow(ctx, `
			SELECT p.owner_id::text, pm.role FROM projects p
			JOIN project_members pm ON pm.project_id = p.id AND pm.user_id = p.owner_id
			WHERE p.id = $1
		`, projectID).Scan(&ownerID, &role); err != nil {
			t.Fatalf("load project %s: %v", projectID, err)
		}
		if ownerID != wantOwner || role != "owner" {
			t.Fatalf("project %s owner=%s role=%s, want %s/owner", projectID, ownerID, role, wantOwner)
		}
	}
	assertOwner(sharedWithManager, manager)
	assertOwner(sharedWithViewer, viewer)

	var soloCount, costItems int
	if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM projects WHERE id = $1`, solo).Scan(&soloCount); err != nil {
		t.Fatalf("count solo project: %v", err)
	}
	if soloCount != 0 {
		t.Fatalf("project without other members should be deleted with the account")
	}
	if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM cost_items WHERE project_id = $1 AND created_by IS NULL`, sharedWithManager).Scan(&costItems); err != nil {
		t.Fatalf("count cost items: %v", err)
	}
	if costItems != 1 {
		t.Fatalf("shared project data must survive with an anonymised author, got %d rows", costItems)
	}
}
