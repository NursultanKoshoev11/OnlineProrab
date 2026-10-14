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
	token, err := signAccessToken(userID)
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
