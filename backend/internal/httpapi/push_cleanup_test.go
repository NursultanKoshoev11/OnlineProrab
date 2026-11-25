package httpapi

import (
	"context"
	"sync"
	"testing"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/notifications"
)

type stalePushSender struct {
	mu      sync.Mutex
	targets []notifications.Target
}

func (s *stalePushSender) Send(_ context.Context, targets []notifications.Target, _, _ string, _ map[string]string) error {
	s.mu.Lock()
	s.targets = append(s.targets, targets...)
	s.mu.Unlock()
	for _, target := range targets {
		if target.ID == "stale-android-fid" {
			return &notifications.SendError{Unregistered: []notifications.Target{target}, Errors: []error{context.Canceled}}
		}
	}
	return nil
}

// A cost item notifies every other member's device and removes installations
// FCM reports as unregistered, keeping the live ones.
func TestCostItemPushForgetsUnregisteredInstallations(t *testing.T) {
	db := openMigratedTestDB(t)
	oldState := appState
	defer func() { appState = oldState }()
	sender := &stalePushSender{}
	appState = State{DB: db, PushSender: sender}
	ctx := context.Background()

	var actor, member, projectID string
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000601') RETURNING id::text`).Scan(&actor); err != nil {
		t.Fatalf("seed actor: %v", err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO users (phone) VALUES ('+996700000602') RETURNING id::text`).Scan(&member); err != nil {
		t.Fatalf("seed member: %v", err)
	}
	if err := db.Pool.QueryRow(ctx, `INSERT INTO projects (owner_id, name) VALUES ($1, 'Объект') RETURNING id::text`, actor).Scan(&projectID); err != nil {
		t.Fatalf("seed project: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `INSERT INTO project_members (project_id, user_id, role) VALUES ($1, $2, 'owner'), ($1, $3, 'worker')`, projectID, actor, member); err != nil {
		t.Fatalf("seed members: %v", err)
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO push_tokens (user_id, token, platform, target_type) VALUES
			($1, 'actor-fid', 'ios', 'fid'),
			($2, 'stale-android-fid', 'android', 'fid'),
			($2, 'live-ios-fid', 'ios', 'fid')
	`, actor, member); err != nil {
		t.Fatalf("seed push tokens: %v", err)
	}

	notifyProjectMembers(ctx, projectID, map[string]struct{}{actor: {}, member: {}}, actor, "")

	sent := map[string]bool{}
	for _, target := range sender.targets {
		sent[target.ID] = true
	}
	if !sent["stale-android-fid"] || !sent["live-ios-fid"] || sent["actor-fid"] {
		t.Fatalf("sent to %v, want both member devices and not the actor", sent)
	}
	rows, err := db.Pool.Query(ctx, `SELECT token FROM push_tokens ORDER BY token`)
	if err != nil {
		t.Fatalf("list tokens: %v", err)
	}
	defer rows.Close()
	var remaining []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			t.Fatalf("scan token: %v", err)
		}
		remaining = append(remaining, token)
	}
	if len(remaining) != 2 || remaining[0] != "actor-fid" || remaining[1] != "live-ios-fid" {
		t.Fatalf("remaining tokens = %v, want the stale installation removed", remaining)
	}
}
