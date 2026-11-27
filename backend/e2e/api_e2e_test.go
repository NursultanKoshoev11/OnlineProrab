//go:build e2e

package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

const (
	e2ePhoneA = "+996700000001"
	e2ePhoneB = "+996700000002"
	// e2ePhoneC is not seeded: logging in creates a fresh account whose session
	// the logout test may revoke without affecting users A and B.
	e2ePhoneC = "+996700000003"
	e2eCode   = "111111"

	e2eUserA    = "00000000-0000-0000-0000-000000000001"
	e2eProjectA = "10000000-0000-0000-0000-000000000001"
	e2eProjectB = "10000000-0000-0000-0000-000000000002"
)

type apiClient struct {
	baseURL string
	http    *http.Client
}

type session struct {
	userID       string
	accessToken  string
	refreshToken string
}

func TestAPIEndToEnd(t *testing.T) {
	baseURL := strings.TrimRight(os.Getenv("E2E_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = "http://127.0.0.1:8080"
	}
	client := &apiClient{baseURL: baseURL, http: &http.Client{Timeout: 20 * time.Second}}
	waitForReady(t, client)

	owner := login(t, client, e2ePhoneA)
	other := login(t, client, e2ePhoneB)

	t.Run("SMS session refresh and logout", func(t *testing.T) {
		session := login(t, client, e2ePhoneC)
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/auth/session/refresh", "", map[string]any{
			"refresh_token": session.refreshToken,
		})
		assertStatus(t, status, body, http.StatusOK)
		var refreshed struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
		}
		decodeJSON(t, body, &refreshed)
		if refreshed.AccessToken == "" || refreshed.RefreshToken == "" {
			t.Fatalf("refresh response did not contain rotated tokens: %s", body)
		}
		status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/auth/session/logout", refreshed.AccessToken, map[string]any{
			"refresh_token": refreshed.RefreshToken,
		})
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects", refreshed.AccessToken, nil, "")
		assertStatus(t, status, body, http.StatusUnauthorized)
	})

	// Create the A-owned records first. B is still independent at this point,
	// so all of these IDs are useful for the cross-user authorization matrix.
	costID := createCostItem(t, client, owner, e2eProjectA)
	taskID := createTask(t, client, owner, e2eProjectA)
	reportID := createDailyReport(t, client, owner, e2eProjectA)
	fileID := uploadReceipt(t, client, owner, e2eProjectA)

	t.Run("user B cannot use user A resource IDs", func(t *testing.T) {
		projectPath := "/api/v1/projects/" + e2eProjectA
		memberPath := "/api/v1/project-members/" + e2eUserA + "?project_id=" + url.QueryEscape(e2eProjectA)
		costPath := "/api/v1/cost-items/" + costID
		reportPath := "/api/v1/daily-reports/" + reportID
		filePath := "/api/v1/files/" + fileID
		taskPath := "/api/v1/tasks/" + taskID

		cases := []struct {
			name        string
			method      string
			path        string
			body        any
			contentType string
		}{
			{"project get", http.MethodGet, projectPath, nil, ""},
			{"project patch", http.MethodPatch, projectPath, map[string]any{"name": "forbidden", "status": "active", "budget_amount": 1, "currency": "KGS", "start_date": "2026-11-18"}, ""},
			{"project delete", http.MethodDelete, projectPath, nil, ""},
			{"member patch", http.MethodPatch, memberPath, map[string]string{"role": "worker"}, ""},
			{"member delete", http.MethodDelete, memberPath, nil, ""},
			{"cost get", http.MethodGet, costPath, nil, ""},
			{"cost patch", http.MethodPatch, costPath, map[string]any{"title": "forbidden", "amount": 1, "currency": "KGS", "spent_at": "2026-11-18"}, ""},
			{"cost delete", http.MethodDelete, costPath, nil, ""},
			{"daily report get", http.MethodGet, reportPath, nil, ""},
			{"daily report patch", http.MethodPatch, reportPath, map[string]any{"summary": "forbidden", "workers_count": 1, "report_date": "2026-11-18"}, ""},
			{"daily report delete", http.MethodDelete, reportPath, nil, ""},
			{"file delete", http.MethodDelete, filePath, nil, ""},
			{"task patch", http.MethodPatch, taskPath, map[string]any{"title": "forbidden", "status": "done", "due_date": "2026-11-18"}, ""},
			{"task delete", http.MethodDelete, taskPath, nil, ""},
			{"file download", http.MethodGet, "/api/v1/files/download?file_id=" + url.QueryEscape(fileID), nil, ""},
			{"project member list", http.MethodGet, "/api/v1/project-members?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"cost list", http.MethodGet, "/api/v1/cost-items?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"daily report list", http.MethodGet, "/api/v1/daily-reports?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"file list", http.MethodGet, "/api/v1/files?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"task list", http.MethodGet, "/api/v1/tasks?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"audit log list", http.MethodGet, "/api/v1/audit-logs?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"realtime project stream", http.MethodGet, "/api/v1/realtime?project_id=" + url.QueryEscape(e2eProjectA), nil, ""},
			{"expense AI search", http.MethodPost, "/api/v1/expense-ai/search", map[string]string{"project_id": e2eProjectA, "query": "cement"}, ""},
			{"cost create", http.MethodPost, "/api/v1/cost-items", map[string]any{"project_id": e2eProjectA, "title": "forbidden", "amount": 1, "currency": "KGS"}, ""},
			{"daily report create", http.MethodPost, "/api/v1/daily-reports", map[string]any{"project_id": e2eProjectA, "summary": "forbidden", "workers_count": 0}, ""},
			{"task create", http.MethodPost, "/api/v1/tasks", map[string]any{"project_id": e2eProjectA, "title": "forbidden"}, ""},
			{"project invite create", http.MethodPost, "/api/v1/project-invites", map[string]any{"project_id": e2eProjectA, "phone": "+996700000003", "role": "worker"}, ""},
		}

		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				var body []byte
				contentType := tc.contentType
				if tc.body != nil {
					body = mustMarshal(t, tc.body)
					contentType = "application/json"
				}
				status, response, _ := client.request(t, tc.method, tc.path, other.accessToken, body, contentType)
				if status != http.StatusForbidden && status != http.StatusNotFound {
					t.Fatalf("expected 403 or 404 for user B, got %d: %s", status, response)
				}
			})
		}

		status, body, _ := client.upload(t, other.accessToken, e2eProjectA, "receipt")
		if status != http.StatusForbidden && status != http.StatusNotFound {
			t.Fatalf("expected 403 or 404 for user B upload, got %d: %s", status, body)
		}
	})

	t.Run("project CRUD and trial project limit", func(t *testing.T) {
		// B starts with one active trial project, so a second create is denied.
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/projects", other.accessToken, map[string]any{
			"name": "trial limit project",
		})
		assertStatus(t, status, body, http.StatusForbidden)

		status, body, _ = client.request(t, http.MethodPatch, "/api/v1/projects/"+e2eProjectB, other.accessToken, mustMarshal(t, map[string]any{
			"name": "updated seeded project", "status": "active", "budget_amount": 50001, "currency": "KGS", "start_date": "2026-11-18",
		}), "application/json")
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects/"+e2eProjectB, other.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)

		status, body, _ = client.request(t, http.MethodDelete, "/api/v1/projects/"+e2eProjectB, other.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)

		status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/projects", other.accessToken, map[string]any{
			"name": "created project", "address": "Local", "budget_amount": 100, "currency": "KGS", "start_date": "2026-11-18",
		})
		assertStatus(t, status, body, http.StatusCreated)
		var created map[string]any
		decodeJSON(t, body, &created)
		createdID := stringField(t, created, "id")

		status, body, _ = client.request(t, http.MethodPatch, "/api/v1/projects/"+createdID, other.accessToken, mustMarshal(t, map[string]any{
			"name": "updated project", "status": "active", "budget_amount": 101, "currency": "KGS", "start_date": "2026-11-18",
		}), "application/json")
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects/"+createdID, other.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodDelete, "/api/v1/projects/"+createdID, other.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
	})

	t.Run("team invite role change and removal", func(t *testing.T) {
		status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/project-invites", owner.accessToken, map[string]any{
			"project_id": e2eProjectA, "phone": e2ePhoneB, "role": "worker",
		})
		assertStatus(t, status, body, http.StatusCreated)

		// An existing account joins only after accepting the invitation.
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects/"+e2eProjectA, other.accessToken, nil, "")
		if status != http.StatusForbidden && status != http.StatusNotFound {
			t.Fatalf("invitee reached the project before accepting: %d %s", status, body)
		}
		acceptIncomingInvite(t, client, other, e2eProjectA)

		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects/"+e2eProjectA, other.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)

		status, body, _ = client.request(t, http.MethodGet, "/api/v1/project-members?project_id="+url.QueryEscape(e2eProjectA), owner.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		var members struct {
			Items []struct {
				UserID string `json:"user_id"`
				Role   string `json:"role"`
			} `json:"items"`
		}
		decodeJSON(t, body, &members)
		memberID := ""
		for _, member := range members.Items {
			if member.UserID == other.userID {
				memberID = member.UserID
				if member.Role != "worker" {
					t.Fatalf("expected worker role after invite, got %q", member.Role)
				}
			}
		}
		if memberID == "" {
			t.Fatalf("invited user %s was not returned in member list: %s", other.userID, body)
		}

		memberPath := "/api/v1/project-members/" + memberID + "?project_id=" + url.QueryEscape(e2eProjectA)
		status, body, _ = client.requestJSON(t, http.MethodPatch, memberPath, owner.accessToken, map[string]string{"role": "viewer"})
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodDelete, memberPath, owner.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		status, body, _ = client.request(t, http.MethodGet, "/api/v1/projects/"+e2eProjectA, other.accessToken, nil, "")
		if status != http.StatusForbidden && status != http.StatusNotFound {
			t.Fatalf("expected removed member to lose access, got %d: %s", status, body)
		}
	})

	t.Run("subscription status", func(t *testing.T) {
		status, body, _ := client.request(t, http.MethodGet, "/api/v1/subscriptions/status", owner.accessToken, nil, "")
		assertStatus(t, status, body, http.StatusOK)
		var subscription map[string]any
		decodeJSON(t, body, &subscription)
		if stringField(t, subscription, "plan") != "standard" || stringField(t, subscription, "status") != "active" {
			t.Fatalf("unexpected seeded subscription: %s", body)
		}
	})
}

func waitForReady(t *testing.T, client *apiClient) {
	t.Helper()
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		request, err := http.NewRequest(http.MethodGet, client.baseURL+"/ready", nil)
		if err == nil {
			response, requestErr := client.http.Do(request)
			if requestErr == nil {
				body, readErr := io.ReadAll(response.Body)
				response.Body.Close()
				if readErr == nil && response.StatusCode == http.StatusOK && strings.Contains(string(body), `"status":"ready"`) {
					return
				}
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	t.Fatalf("API did not become ready at %s", client.baseURL)
}

func login(t *testing.T, client *apiClient, phone string) session {
	t.Helper()
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/auth/sms/request", "", map[string]string{"phone": phone})
	assertStatus(t, status, body, http.StatusAccepted)
	var requestResponse map[string]any
	decodeJSON(t, body, &requestResponse)
	if stringField(t, requestResponse, "dev_code") != e2eCode {
		t.Fatalf("development SMS response did not contain the fixed code: %s", body)
	}

	status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/auth/sms/verify", "", map[string]string{"phone": phone, "code": e2eCode})
	assertStatus(t, status, body, http.StatusOK)
	var verified map[string]any
	decodeJSON(t, body, &verified)
	bootstrapToken := stringField(t, verified, "access_token")
	userID := stringField(t, verified, "user_id")

	status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/auth/session", bootstrapToken, map[string]string{"device_name": "e2e"})
	assertStatus(t, status, body, http.StatusCreated)
	var sessionResponse map[string]any
	decodeJSON(t, body, &sessionResponse)
	return session{
		userID:       userID,
		accessToken:  stringField(t, sessionResponse, "access_token"),
		refreshToken: stringField(t, sessionResponse, "refresh_token"),
	}
}

// acceptIncomingInvite accepts the invitee's pending invitation to projectID.
func acceptIncomingInvite(t *testing.T, client *apiClient, invitee session, projectID string) {
	t.Helper()
	status, body, _ := client.request(t, http.MethodGet, "/api/v1/project-invites/incoming", invitee.accessToken, nil, "")
	assertStatus(t, status, body, http.StatusOK)
	var incoming struct {
		Items []struct {
			ID        string `json:"id"`
			ProjectID string `json:"project_id"`
		} `json:"items"`
	}
	decodeJSON(t, body, &incoming)
	for _, invite := range incoming.Items {
		if invite.ProjectID == projectID {
			status, body, _ = client.requestJSON(t, http.MethodPost, "/api/v1/project-invites/incoming/accept", invitee.accessToken, map[string]string{"invite_id": invite.ID})
			assertStatus(t, status, body, http.StatusOK)
			return
		}
	}
	t.Fatalf("no pending invitation to %s for the invitee: %s", projectID, body)
}

func createCostItem(t *testing.T, client *apiClient, owner session, projectID string) string {
	t.Helper()
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/cost-items", owner.accessToken, map[string]any{
		"project_id": projectID, "title": "E2E cement", "description": "API test", "amount": 1250, "currency": "KGS", "spent_at": "2026-11-18",
	})
	assertStatus(t, status, body, http.StatusCreated)
	var item map[string]any
	decodeJSON(t, body, &item)
	return stringField(t, item, "id")
}

func createTask(t *testing.T, client *apiClient, owner session, projectID string) string {
	t.Helper()
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/tasks", owner.accessToken, map[string]any{
		"project_id": projectID, "title": "E2E task", "description": "API test", "status": "open", "due_date": "2026-11-18",
	})
	assertStatus(t, status, body, http.StatusCreated)
	var item map[string]any
	decodeJSON(t, body, &item)
	return stringField(t, item, "id")
}

func createDailyReport(t *testing.T, client *apiClient, owner session, projectID string) string {
	t.Helper()
	status, body, _ := client.requestJSON(t, http.MethodPost, "/api/v1/daily-reports", owner.accessToken, map[string]any{
		"project_id": projectID, "report_date": "2026-11-18", "summary": "E2E report", "workers_count": 2, "issues": "none",
	})
	assertStatus(t, status, body, http.StatusCreated)
	var item map[string]any
	decodeJSON(t, body, &item)
	return stringField(t, item, "id")
}

func uploadReceipt(t *testing.T, client *apiClient, owner session, projectID string) string {
	t.Helper()
	status, body, _ := client.upload(t, owner.accessToken, projectID, "receipt")
	assertStatus(t, status, body, http.StatusCreated)
	var item map[string]any
	decodeJSON(t, body, &item)
	fileID := stringField(t, item, "id")

	status, body, headers := client.request(t, http.MethodGet, "/api/v1/files/download?file_id="+url.QueryEscape(fileID), owner.accessToken, nil, "")
	assertStatus(t, status, body, http.StatusOK)
	if headers.Get("Content-Type") != "application/pdf" && !strings.HasPrefix(headers.Get("Content-Type"), "application/pdf;") {
		t.Fatalf("download content type was %q", headers.Get("Content-Type"))
	}
	if !bytes.HasPrefix(body, []byte("%PDF-1.4")) {
		t.Fatalf("download did not return the uploaded PDF bytes: %q", body)
	}
	return fileID
}

func (c *apiClient) upload(t *testing.T, token, projectID, kind string) (int, []byte, http.Header) {
	t.Helper()
	var buffer bytes.Buffer
	writer := multipart.NewWriter(&buffer)
	_ = writer.WriteField("project_id", projectID)
	_ = writer.WriteField("kind", kind)
	part, err := writer.CreateFormFile("file", "e2e-receipt.pdf")
	if err != nil {
		t.Fatal(err)
	}
	_, _ = part.Write([]byte("%PDF-1.4\n% e2e\n"))
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return c.request(t, http.MethodPost, "/api/v1/files/upload", token, buffer.Bytes(), writer.FormDataContentType())
}

func (c *apiClient) requestJSON(t *testing.T, method, path, token string, value any) (int, []byte, http.Header) {
	t.Helper()
	return c.request(t, method, path, token, mustMarshal(t, value), "application/json")
}

func (c *apiClient) request(t *testing.T, method, path, token string, body []byte, contentType string) (int, []byte, http.Header) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, responseBody, resp.Header
}

func assertStatus(t *testing.T, status int, body []byte, expected int) {
	t.Helper()
	if status != expected {
		t.Fatalf("expected HTTP %d, got %d: %s", expected, status, body)
	}
}

func mustMarshal(t *testing.T, value any) []byte {
	t.Helper()
	body, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func decodeJSON(t *testing.T, body []byte, value any) {
	t.Helper()
	if err := json.Unmarshal(body, value); err != nil {
		t.Fatalf("invalid JSON response %q: %v", body, err)
	}
}

func stringField(t *testing.T, value map[string]any, field string) string {
	t.Helper()
	result, ok := value[field].(string)
	if !ok || strings.TrimSpace(result) == "" {
		t.Fatalf("response field %q missing or empty: %#v", field, value)
	}
	return result
}

func (c *apiClient) String() string {
	return fmt.Sprintf("apiClient(%s)", c.baseURL)
}
