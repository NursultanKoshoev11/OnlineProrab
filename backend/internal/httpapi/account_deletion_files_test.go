package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

// Deleting a member's account must keep what they uploaded to other people's
// projects; only files of deleted projects and personal files are purged.
func TestDeleteAccountKeepsUploadsInOtherPeoplesProjects(t *testing.T) {
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
	seedProject := func(ownerID string) string {
		var id string
		if err := db.Pool.QueryRow(ctx, `INSERT INTO projects (owner_id, name) VALUES ($1, 'Объект') RETURNING id::text`, ownerID).Scan(&id); err != nil {
			t.Fatalf("seed project: %v", err)
		}
		if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'owner')`, id, ownerID); err != nil {
			t.Fatalf("seed owner membership: %v", err)
		}
		return id
	}
	seedFile := func(projectID *string, uploadedBy, path string) {
		if _, err := db.Pool.Exec(ctx, `
			INSERT INTO files (project_id, uploaded_by, kind, original_name, storage_path, content_type, size_bytes)
			VALUES ($1, $2, 'photo', 'photo.jpg', $3, 'image/jpeg', 10)
		`, projectID, uploadedBy, path); err != nil {
			t.Fatalf("seed file %s: %v", path, err)
		}
	}
	queued := func(path string) bool {
		t.Helper()
		var exists bool
		if err := db.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM file_storage_deletions WHERE storage_path = $1)`, path).Scan(&exists); err != nil {
			t.Fatalf("check deletion queue for %s: %v", path, err)
		}
		return exists
	}
	deleteAccount := func(userID string) {
		t.Helper()
		request := httptest.NewRequest(http.MethodDelete, "/api/v1/account", nil)
		request = request.WithContext(withUserID(request.Context(), userID))
		response := httptest.NewRecorder()
		DeleteAccount(response, request)
		if response.Code != http.StatusOK {
			t.Fatalf("delete account: %d %s", response.Code, response.Body.String())
		}
	}

	owner := seedUser("+996700000501")
	worker := seedUser("+996700000502")
	shared := seedProject(owner)
	if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'worker')`, shared, worker); err != nil {
		t.Fatalf("seed worker membership: %v", err)
	}
	workerSolo := seedProject(worker)
	seedFile(&shared, worker, "projects/shared/worker-receipt.jpg")
	seedFile(&workerSolo, worker, "projects/worker-solo/photo.jpg")
	seedFile(nil, worker, "personal/worker-avatar.jpg")

	deleteAccount(worker)

	if queued("projects/shared/worker-receipt.jpg") {
		t.Fatalf("a member's upload to someone else's project must not be deleted from storage")
	}
	var survivors int
	if err := db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM files WHERE storage_path = 'projects/shared/worker-receipt.jpg' AND uploaded_by IS NULL`).Scan(&survivors); err != nil {
		t.Fatalf("count surviving shared file: %v", err)
	}
	if survivors != 1 {
		t.Fatalf("shared project file row must survive with an anonymised uploader, got %d", survivors)
	}
	if !queued("projects/worker-solo/photo.jpg") {
		t.Fatalf("files of the deleted user's own project must be purged from storage")
	}
	if !queued("personal/worker-avatar.jpg") {
		t.Fatalf("personal files without a project must be purged with the account")
	}
}
