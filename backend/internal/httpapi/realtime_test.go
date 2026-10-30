package httpapi

import "testing"

func TestCostItemPushMessageFormatting(t *testing.T) {
	message := func(details costItemPushDetails) string {
		actor := sanitizeNotificationText(details.ActorName, "Участник проекта")
		expense := sanitizeNotificationText(details.Title, "Расход")
		return actor + " добавил расход «" + expense + "» на " + formatNotificationAmount(details.Amount) + " " + notificationCurrency(details.Currency)
	}(costItemPushDetails{
		ActorName: "Нурсултан Кошоев",
		Title:     "Бетон",
		Amount:    1250.5,
		Currency:  "KGS",
	})

	want := "Нурсултан Кошоев добавил расход «Бетон» на 1 250,5 сом"
	if message != want {
		t.Fatalf("unexpected notification body: got %q, want %q", message, want)
	}
}

func TestNotificationHelpersFallbackAndCurrency(t *testing.T) {
	if got := sanitizeNotificationText("\n\t", "Участник проекта"); got != "Участник проекта" {
		t.Fatalf("fallback actor: got %q", got)
	}
	if got := formatNotificationAmount(100); got != "100" {
		t.Fatalf("integer amount: got %q", got)
	}
	if got := notificationCurrency("usd"); got != "USD" {
		t.Fatalf("currency: got %q", got)
	}
}

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
