package httpapi

import "testing"

func TestRealtimeHubLimitsConnectionsPerUser(t *testing.T) {
	hub := realtimeHub{subscribers: make(map[uint64]*realtimeSubscriber)}
	cleanups := make([]func(), 0, maxRealtimeConnectionsPerUser)
	for i := 0; i < maxRealtimeConnectionsPerUser; i++ {
		_, cleanup, ok := hub.subscribe("user-1", "project-1")
		if !ok || cleanup == nil {
			t.Fatalf("connection %d was rejected before the per-user limit", i+1)
		}
		cleanups = append(cleanups, cleanup)
	}
	if _, cleanup, ok := hub.subscribe("user-1", "project-1"); ok || cleanup != nil {
		t.Fatal("connection above the per-user limit was accepted")
	}
	for _, cleanup := range cleanups {
		cleanup()
	}
}

func TestRealtimeHubAllowsDifferentUsersAfterPerUserLimit(t *testing.T) {
	hub := realtimeHub{subscribers: make(map[uint64]*realtimeSubscriber)}
	cleanups := make([]func(), 0, maxRealtimeConnectionsPerUser)
	for i := 0; i < maxRealtimeConnectionsPerUser; i++ {
		_, cleanup, ok := hub.subscribe("user-1", "project-1")
		if !ok {
			t.Fatalf("connection %d was rejected unexpectedly", i+1)
		}
		cleanups = append(cleanups, cleanup)
	}
	_, otherCleanup, ok := hub.subscribe("user-2", "project-1")
	if !ok || otherCleanup == nil {
		t.Fatal("a different user should not be blocked by another user's limit")
	}
	otherCleanup()
	for _, cleanup := range cleanups {
		cleanup()
	}
}
