//go:build e2e

package e2e

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"testing"
	"time"
)

const (
	notifyOwnerPhone    = "+996700000005"
	notifyWorkerPhone   = "+996700000006"
	notifyViewerPhone   = "+996700000007"
	notifyOutsiderPhone = "+996700000008"
	notifyProject       = "10000000-0000-0000-0000-000000000005"
)

type fakeFCMMessage struct {
	Token        string `json:"token"`
	FID          string `json:"fid"`
	Notification struct {
		Title string `json:"title"`
		Body  string `json:"body"`
	} `json:"notification"`
	Data map[string]string `json:"data"`
}

// TestProjectNotificationsReachAllMembers covers what users expect when
// several accounts share one project: when one member adds an expense, every
// other member gets a push notification and a live realtime event, while the
// author and people outside the project get no push.
func TestProjectNotificationsReachAllMembers(t *testing.T) {
	baseURL := strings.TrimRight(os.Getenv("E2E_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8080"
	}
	fcmURL := strings.TrimRight(os.Getenv("E2E_FAKE_FCM_URL"), "/")
	if fcmURL == "" {
		fcmURL = "http://127.0.0.1:8090"
	}
	client := &apiClient{baseURL: baseURL, http: &http.Client{Timeout: 20 * time.Second}}
	waitForReady(t, client)

	owner := login(t, client, notifyOwnerPhone)
	worker := login(t, client, notifyWorkerPhone)
	viewer := login(t, client, notifyViewerPhone)
	outsider := login(t, client, notifyOutsiderPhone)

	for phone, role := range map[string]string{notifyWorkerPhone: "worker", notifyViewerPhone: "viewer"} {
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/project-invites", owner.accessToken, map[string]any{
			"project_id": notifyProject, "phone": phone, "role": role,
		})
		assertStatus(t, status, body, http.StatusCreated)
	}

	for token, user := range map[string]session{
		"e2e-push-owner":    owner,
		"e2e-push-worker":   worker,
		"e2e-push-viewer":   viewer,
		"e2e-push-outsider": outsider,
	} {
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/push-tokens", user.accessToken, map[string]string{
			"token": token, "target_type": "token", "platform": "android",
		})
		assertStatus(t, status, body, http.StatusNoContent)
	}

	// Every member, including the author, watches the project live.
	ownerEvents := openRealtime(t, client, owner, notifyProject)
	workerEvents := openRealtime(t, client, worker, notifyProject)
	viewerEvents := openRealtime(t, client, viewer, notifyProject)

	t.Run("worker expense notifies owner and viewer only", func(t *testing.T) {
		clearFakeFCM(t, fcmURL)
		itemID := createNamedCostItem(t, client, worker, notifyProject, "Арматура 12 мм", 48500)

		messages := waitForFakeFCM(t, fcmURL, 2)
		assertPushRecipients(t, messages, []string{"e2e-push-owner", "e2e-push-viewer"})
		for _, message := range messages {
			if message.Notification.Title != "Новый расход" {
				t.Errorf("push title = %q, want %q", message.Notification.Title, "Новый расход")
			}
			if !strings.Contains(message.Notification.Body, "Арматура 12 мм") || !strings.Contains(message.Notification.Body, "48") {
				t.Errorf("push body %q does not name the expense and amount", message.Notification.Body)
			}
			if message.Data["type"] != "cost_item_created" || message.Data["project_id"] != notifyProject || message.Data["cost_item_id"] != itemID {
				t.Errorf("push data = %v, want cost_item_created for %s/%s", message.Data, notifyProject, itemID)
			}
		}

		expectRealtimeEvent(t, "owner", ownerEvents, itemID)
		expectRealtimeEvent(t, "viewer", viewerEvents, itemID)
		expectRealtimeEvent(t, "worker (author)", workerEvents, itemID)
	})

	t.Run("owner expense names the owner and skips the owner", func(t *testing.T) {
		clearFakeFCM(t, fcmURL)
		itemID := createNamedCostItem(t, client, owner, notifyProject, "Цемент М500", 12500)
		messages := waitForFakeFCM(t, fcmURL, 2)
		assertPushRecipients(t, messages, []string{"e2e-push-viewer", "e2e-push-worker"})
		for _, message := range messages {
			if !strings.Contains(message.Notification.Body, "Прораб Азамат") {
				t.Errorf("push body %q does not name the author", message.Notification.Body)
			}
		}
		expectRealtimeEvent(t, "worker", workerEvents, itemID)
		expectRealtimeEvent(t, "viewer", viewerEvents, itemID)
	})

	t.Run("removed member stops receiving notifications", func(t *testing.T) {
		memberPath := "/api/v1/project-members/" + viewer.userID + "?project_id=" + url.QueryEscape(notifyProject)
		status, body, _ := client.request(t, http.MethodDelete, memberPath, owner.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)

		clearFakeFCM(t, fcmURL)
		createNamedCostItem(t, client, owner, notifyProject, "Кирпич", 9000)
		messages := waitForFakeFCM(t, fcmURL, 1)
		assertPushRecipients(t, messages, []string{"e2e-push-worker"})
	})
}

func createNamedCostItem(t *testing.T, client *apiClient, author session, projectID, title string, amount int) string {
	t.Helper()
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/cost-items", author.accessToken, map[string]any{
		"project_id": projectID, "title": title, "description": "notification E2E", "amount": amount, "currency": "KGS", "spent_at": "2026-11-18",
	})
	assertStatus(t, status, body, http.StatusCreated)
	var item map[string]any
	decodeJSON(t, body, &item)
	return stringField(t, item, "id")
}

func clearFakeFCM(t *testing.T, fcmURL string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodDelete, fcmURL+"/messages", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("fake FCM is not reachable at %s (start the stack with fake-fcm credentials): %v", fcmURL, err)
	}
	response.Body.Close()
}

// waitForFakeFCM waits until at least want messages arrived, then waits a
// little longer so unexpected extra recipients are caught as well.
func waitForFakeFCM(t *testing.T, fcmURL string, want int) []fakeFCMMessage {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	var messages []fakeFCMMessage
	for time.Now().Before(deadline) {
		messages = readFakeFCM(t, fcmURL)
		if len(messages) >= want {
			time.Sleep(1500 * time.Millisecond)
			return readFakeFCM(t, fcmURL)
		}
		time.Sleep(250 * time.Millisecond)
	}
	t.Fatalf("got %d push notifications within 15s, want %d: %+v", len(messages), want, messages)
	return nil
}

func readFakeFCM(t *testing.T, fcmURL string) []fakeFCMMessage {
	t.Helper()
	response, err := http.Get(fcmURL + "/messages")
	if err != nil {
		t.Fatalf("read fake FCM: %v", err)
	}
	defer response.Body.Close()
	var payload struct {
		Messages []fakeFCMMessage `json:"messages"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode fake FCM messages: %v", err)
	}
	return payload.Messages
}

func assertPushRecipients(t *testing.T, messages []fakeFCMMessage, want []string) {
	t.Helper()
	got := make([]string, 0, len(messages))
	for _, message := range messages {
		got = append(got, message.Token+message.FID)
	}
	sort.Strings(got)
	sort.Strings(want)
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("push recipients = %v, want exactly %v", got, want)
	}
}

type realtimeEvent struct {
	ProjectID  string `json:"project_id"`
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id"`
	Action     string `json:"action"`
}

// openRealtime subscribes to the project's server-sent event stream and
// forwards decoded events until the test ends.
func openRealtime(t *testing.T, client *apiClient, user session, projectID string) <-chan realtimeEvent {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, client.baseURL+"/api/v1/realtime?project_id="+url.QueryEscape(projectID), nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+user.accessToken)
	req.Header.Set("Accept", "text/event-stream")
	response, err := (&http.Client{}).Do(req)
	if err != nil {
		t.Fatalf("open realtime stream: %v", err)
	}
	if response.StatusCode != http.StatusOK {
		response.Body.Close()
		t.Fatalf("realtime stream returned %d", response.StatusCode)
	}
	events := make(chan realtimeEvent, 32)
	go func() {
		defer response.Body.Close()
		scanner := bufio.NewScanner(response.Body)
		for scanner.Scan() {
			line := scanner.Text()
			if !strings.HasPrefix(line, "data: ") {
				continue
			}
			var event realtimeEvent
			if json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &event) == nil {
				select {
				case events <- event:
				default:
				}
			}
		}
	}()
	// Give the server a moment to register the subscription before events
	// are published.
	time.Sleep(300 * time.Millisecond)
	return events
}

func expectRealtimeEvent(t *testing.T, name string, events <-chan realtimeEvent, itemID string) {
	t.Helper()
	timeout := time.After(5 * time.Second)
	for {
		select {
		case event := <-events:
			if event.EntityType == "cost_item" && event.EntityID == itemID && event.Action == "created" {
				return
			}
		case <-timeout:
			t.Errorf("%s did not receive the realtime cost_item created event for %s", name, itemID)
			return
		}
	}
}
