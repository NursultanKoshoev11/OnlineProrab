package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
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

var projectRealtime = realtimeHub{
	subscribers: make(map[uint64]*realtimeSubscriber),
}

func (h *realtimeHub) subscribe(userID, projectID string) (<-chan []byte, func()) {
	id := atomic.AddUint64(&h.nextID, 1)
	subscriber := &realtimeSubscriber{
		userID: userID, projectID: projectID, events: make(chan []byte, 32),
	}
	h.mu.Lock()
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
	}
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
			log.Printf("realtime subscriber buffer full user_id=%s project_id=%s", subscriber.userID, projectID)
		}
	}
}

func publishProjectEvent(projectID, entityType, entityID, action string, extraUserIDs ...string) {
	projectID = strings.TrimSpace(projectID)
	if projectID == "" || appState.DB == nil || appState.DB.Pool == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	rows, err := appState.DB.Pool.Query(ctx,
		"SELECT user_id::text FROM project_members WHERE project_id = $1", projectID)
	if err != nil {
		log.Printf("realtime membership lookup failed project_id=%s error=%v", projectID, err)
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
		log.Printf("realtime membership rows failed project_id=%s error=%v", projectID, err)
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
		log.Printf("realtime event marshal failed project_id=%s error=%v", projectID, err)
		return
	}
	projectRealtime.publish(projectID, userIDs, payload)
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
	events, unsubscribe := projectRealtime.subscribe(userID, projectID)
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
