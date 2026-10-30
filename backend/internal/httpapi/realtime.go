package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type realtimeEvent struct {
	ID         string `json:"id"`
	ProjectID  string `json:"project_id"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id,omitempty"`
	Action     string `json:"action"`
	CreatedAt  string `json:"created_at"`
}

type realtimeSubscriber struct {
	userID    string
	projectID string
	events    chan []byte
}

type realtimeHub struct {
	mu          sync.RWMutex
	nextID      uint64
	subscribers map[uint64]*realtimeSubscriber
}

const (
	maxRealtimeConnections        = 256
	maxRealtimeConnectionsPerUser = 8
)

var projectRealtime = realtimeHub{
	subscribers: make(map[uint64]*realtimeSubscriber),
}

func (h *realtimeHub) subscribe(userID, projectID string) (<-chan []byte, func(), bool) {
	h.mu.Lock()
	if len(h.subscribers) >= maxRealtimeConnections {
		h.mu.Unlock()
		return nil, nil, false
	}
	userConnections := 0
	for _, existing := range h.subscribers {
		if existing.userID == userID {
			userConnections++
		}
	}
	if userConnections >= maxRealtimeConnectionsPerUser {
		h.mu.Unlock()
		return nil, nil, false
	}
	id := atomic.AddUint64(&h.nextID, 1)
	subscriber := &realtimeSubscriber{
		userID: userID, projectID: projectID, events: make(chan []byte, 32),
	}
	h.subscribers[id] = subscriber
	h.mu.Unlock()

	var once sync.Once
	return subscriber.events, func() {
		once.Do(func() {
			h.mu.Lock()
			delete(h.subscribers, id)
			close(subscriber.events)
			h.mu.Unlock()
		})
	}, true
}

func (h *realtimeHub) publish(projectID string, userIDs map[string]struct{}, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, subscriber := range h.subscribers {
		if subscriber.projectID != "" && subscriber.projectID != projectID {
			continue
		}
		if _, ok := userIDs[subscriber.userID]; !ok {
			continue
		}
		select {
		case subscriber.events <- payload:
		default:
			slog.Warn("realtime_subscriber_backpressure", "project_id", projectID)
		}
	}
}

func publishProjectEvent(projectID, entityType, entityID, action string, extraUserIDs ...string) {
	publishProjectEventForActor(projectID, entityType, entityID, action, "", extraUserIDs...)
}

func publishProjectEventForActor(projectID, entityType, entityID, action, actorID string, extraUserIDs ...string) {
	projectID = strings.TrimSpace(projectID)
	if projectID == "" || appState.DB == nil || appState.DB.Pool == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	rows, err := appState.DB.Pool.Query(ctx,
		"SELECT user_id::text FROM project_members WHERE project_id = $1", projectID)
	if err != nil {
		slog.Error("realtime_membership_lookup_failed", "project_id", projectID, "error", err)
		return
	}
	defer rows.Close()

	userIDs := make(map[string]struct{})
	for rows.Next() {
		var userID string
		if rows.Scan(&userID) == nil {
			userIDs[userID] = struct{}{}
		}
	}
	if err := rows.Err(); err != nil {
		slog.Error("realtime_membership_rows_failed", "project_id", projectID, "error", err)
		return
	}
	for _, userID := range extraUserIDs {
		if userID != "" {
			userIDs[userID] = struct{}{}
		}
	}
	event := realtimeEvent{
		ID:         fmt.Sprintf("%d", time.Now().UTC().UnixNano()),
		ProjectID:  projectID,
		EntityType: entityType,
		EntityID:   entityID,
		Action:     action,
		CreatedAt:  time.Now().UTC().Format(time.RFC3339Nano),
	}
	payload, err := json.Marshal(event)
	if err != nil {
		slog.Error("realtime_event_marshal_failed", "project_id", projectID, "error", err)
		return
	}
	projectRealtime.publish(projectID, userIDs, payload)
	if entityType == "cost_item" && action == "created" && appState.PushSender != nil {
		// Push delivery must not add provider latency to the cost-item response.
		go notifyProjectMembers(context.Background(), projectID, userIDs, actorID, entityID)
	}
}

func notifyProjectMembers(ctx context.Context, projectID string, userIDs map[string]struct{}, actorID, entityID string) {
	ids := make([]string, 0, len(userIDs))
	for userID := range userIDs {
		if userID != "" && userID != actorID {
			ids = append(ids, userID)
		}
	}
	if len(ids) == 0 {
		return
	}
	rows, err := appState.DB.Pool.Query(ctx, `SELECT token FROM push_tokens WHERE user_id = ANY($1::uuid[])`, ids)
	if err != nil {
		slog.Error("push_token_lookup_failed", "project_id", projectID, "error", err)
		return
	}
	defer rows.Close()
	tokens := make([]string, 0)
	for rows.Next() {
		var token string
		if rows.Scan(&token) == nil {
			tokens = append(tokens, token)
		}
	}
	if err := rows.Err(); err != nil || len(tokens) == 0 {
		return
	}
	title, body := costItemPushMessage(ctx, projectID, entityID)
	pushCtx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	if err := appState.PushSender.Send(pushCtx, tokens, title, body, map[string]string{
		"type":         "cost_item_created",
		"project_id":   projectID,
		"cost_item_id": entityID,
		"click_action": "OPEN_PROJECT_EXPENSES",
	}); err != nil {
		slog.Error("firebase_push_notification_failed", "project_id", projectID, "error", err)
	}
}

type costItemPushDetails struct {
	ActorName string
	Title     string
	Amount    float64
	Currency  string
}

func costItemPushMessage(ctx context.Context, projectID, entityID string) (string, string) {
	const fallbackTitle = "Новый расход"
	const fallbackBody = "В проект добавлен новый расход."

	detailsCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	var details costItemPushDetails
	err := appState.DB.Pool.QueryRow(detailsCtx, `
		SELECT COALESCE(NULLIF(u.name, ''), NULLIF(u.phone, ''), 'Участник проекта'),
		       c.title, c.amount::float8, COALESCE(NULLIF(c.currency, ''), 'KGS')
		FROM cost_items c
		LEFT JOIN users u ON u.id = c.created_by
		WHERE c.id = $1 AND c.project_id = $2 AND c.deleted_at IS NULL
	`, entityID, projectID).Scan(&details.ActorName, &details.Title, &details.Amount, &details.Currency)
	if err != nil {
		slog.Warn("push_notification_details_lookup_failed", "project_id", projectID, "cost_item_id", entityID, "error", err)
		return fallbackTitle, fallbackBody
	}

	actor := sanitizeNotificationText(details.ActorName, "Участник проекта")
	expense := sanitizeNotificationText(details.Title, "Расход")
	unit := notificationCurrency(details.Currency)
	body := fmt.Sprintf("%s добавил расход «%s» на %s %s", actor, expense, formatNotificationAmount(details.Amount), unit)
	return fallbackTitle, body
}

func sanitizeNotificationText(value, fallback string) string {
	value = strings.Join(strings.Fields(strings.TrimSpace(value)), " ")
	if value == "" {
		return fallback
	}
	runes := []rune(value)
	const maxLength = 96
	if len(runes) > maxLength {
		return string(runes[:maxLength-1]) + "…"
	}
	return value
}

func formatNotificationAmount(amount float64) string {
	value := fmt.Sprintf("%.2f", amount)
	parts := strings.SplitN(value, ".", 2)
	integer := parts[0]
	for index := len(integer) - 3; index > 0; index -= 3 {
		integer = integer[:index] + " " + integer[index:]
	}
	if len(parts) == 1 {
		return integer
	}
	fraction := strings.TrimRight(parts[1], "0")
	if fraction == "" {
		return integer
	}
	return integer + "," + fraction
}

func notificationCurrency(currency string) string {
	switch strings.ToUpper(strings.TrimSpace(currency)) {
	case "", "KGS":
		return "сом"
	default:
		return strings.ToUpper(strings.TrimSpace(currency))
	}
}

func RealtimeEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	userID := userIDFromContext(r.Context())
	projectID := strings.TrimSpace(r.URL.Query().Get("project_id"))
	if projectID != "" && !canAccessProject(r.Context(), userID, projectID) {
		Error(w, http.StatusForbidden, "project access denied")
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		Error(w, http.StatusInternalServerError, "streaming is not supported")
		return
	}
	events, unsubscribe, ok := projectRealtime.subscribe(userID, projectID)
	if !ok {
		w.Header().Set("Retry-After", "10")
		Error(w, http.StatusTooManyRequests, "too many realtime connections")
		return
	}
	defer unsubscribe()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache, no-store")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprint(w, "retry: 2000\n\n")
	flusher.Flush()

	keepAlive := time.NewTicker(20 * time.Second)
	defer keepAlive.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case payload, ok := <-events:
			if !ok {
				return
			}
			_, _ = fmt.Fprintf(w, "event: change\ndata: %s\n\n", payload)
			flusher.Flush()
		case <-keepAlive.C:
			_, _ = fmt.Fprint(w, ": keep-alive\n\n")
			flusher.Flush()
		}
	}
}
