package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type supportTicketRequest struct {
	Channel string
	Subject string
	Message string
}

type supportTicket struct {
	ID             string
	Channel        string
	Subject        string
	Message        string
	DeliveryStatus string
	CreatedAt      time.Time
}

func SupportChannels(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	JSON(w, http.StatusOK, map[string]any{
		"telegram": map[string]any{
			"enabled": telegramSupportConfigured(),
			"url":     appState.SupportTelegramURL,
		},
		"whatsapp": map[string]any{
			"enabled": whatsappSupportConfigured(),
			"url":     appState.SupportWhatsAppURL,
		},
	})
}

func SupportTickets(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	var req supportTicketRequest
	decoder := json.NewDecoder(io.LimitReader(r.Body, 8*1024))
	if err := decoder.Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.Channel = strings.ToLower(strings.TrimSpace(req.Channel))
	req.Subject = strings.TrimSpace(req.Subject)
	req.Message = strings.TrimSpace(req.Message)
	if req.Channel != "telegram" && req.Channel != "whatsapp" {
		Error(w, http.StatusBadRequest, "channel must be telegram or whatsapp")
		return
	}
	if len(req.Subject) > 120 {
		Error(w, http.StatusBadRequest, "subject is too long")
		return
	}
	if req.Message == "" || len(req.Message) > 4000 {
		Error(w, http.StatusBadRequest, "message must contain 1 to 4000 characters")
		return
	}
	userID := userIDFromContext(r.Context())
	if userID == "" {
		Error(w, http.StatusUnauthorized, "authentication required")
		return
	}
	ticket, err := createSupportTicket(r.Context(), userID, req)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to save support request")
		return
	}
	status, deliveryErr := deliverSupportTicket(r.Context(), userID, ticket)
	ticket.DeliveryStatus = status
	if deliveryErr != "" {
		_ = updateSupportDelivery(r.Context(), ticket.ID, status, deliveryErr)
	} else {
		_ = updateSupportDelivery(r.Context(), ticket.ID, status, "")
	}
	JSON(w, http.StatusCreated, map[string]any{
		"id":              ticket.ID,
		"channel":         ticket.Channel,
		"subject":         ticket.Subject,
		"message":         ticket.Message,
		"delivery_status": ticket.DeliveryStatus,
		"created_at":      ticket.CreatedAt,
	})
}

func createSupportTicket(ctx context.Context, userID string, req supportTicketRequest) (supportTicket, error) {
	const query = "INSERT INTO support_tickets (user_id, channel, subject, message) VALUES ($1, $2, $3, $4) RETURNING id::text, created_at"
	ticket := supportTicket{Channel: req.Channel, Subject: req.Subject, Message: req.Message}
	err := appState.DB.Pool.QueryRow(ctx, query, userID, req.Channel, req.Subject, req.Message).
		Scan(&ticket.ID, &ticket.CreatedAt)
	if err != nil {
		return supportTicket{}, err
	}
	return ticket, nil
}

func updateSupportDelivery(ctx context.Context, ticketID, status, deliveryErr string) error {
	const query = "UPDATE support_tickets SET delivery_status = $1, delivery_error = NULLIF($2, ''), updated_at = now() WHERE id = $3"
	_, err := appState.DB.Pool.Exec(ctx, query, status, deliveryErr, ticketID)
	return err
}

func telegramSupportConfigured() bool {
	return strings.TrimSpace(appState.SupportTelegramBotToken) != "" &&
		strings.TrimSpace(appState.SupportTelegramChatID) != ""
}

func whatsappSupportConfigured() bool {
	return strings.TrimSpace(appState.SupportWhatsAppToken) != "" &&
		strings.TrimSpace(appState.SupportWhatsAppPhoneID) != "" &&
		strings.TrimSpace(appState.SupportWhatsAppTo) != ""
}

func deliverSupportTicket(ctx context.Context, userID string, ticket supportTicket) (string, string) {
	var phone string
	_ = appState.DB.Pool.QueryRow(ctx, "SELECT COALESCE(phone, '') FROM users WHERE id = $1", userID).Scan(&phone)
	text := fmt.Sprintf("STROY support\nUser: %s\nPhone: %s\nSubject: %s\n\n%s", userID, phone, ticket.Subject, ticket.Message)
	switch ticket.Channel {
	case "telegram":
		if !telegramSupportConfigured() {
			return "not_configured", ""
		}
		if err := sendTelegramSupport(ctx, text); err != nil {
			return "failed", err.Error()
		}
	case "whatsapp":
		if !whatsappSupportConfigured() {
			return "not_configured", ""
		}
		if err := sendWhatsAppSupport(ctx, text); err != nil {
			return "failed", err.Error()
		}
	}
	return "sent", ""
}

func sendTelegramSupport(ctx context.Context, text string) error {
	endpoint := "https://api.telegram.org/bot" + appState.SupportTelegramBotToken + "/sendMessage"
	payload := map[string]any{
		"chat_id":                  appState.SupportTelegramChatID,
		"text":                     text,
		"disable_web_page_preview": true,
	}
	return postSupportJSON(ctx, endpoint, "", payload)
}

func sendWhatsAppSupport(ctx context.Context, text string) error {
	endpoint := "https://graph.facebook.com/v20.0/" + appState.SupportWhatsAppPhoneID + "/messages"
	payload := map[string]any{
		"messaging_product": "whatsapp",
		"to":                appState.SupportWhatsAppTo,
		"type":              "text",
		"text":              map[string]any{"preview_url": false, "body": text},
	}
	return postSupportJSON(ctx, endpoint, "Bearer "+appState.SupportWhatsAppToken, payload)
}

func postSupportJSON(ctx context.Context, endpoint, authorization string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	requestCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if authorization != "" {
		req.Header.Set("Authorization", authorization)
	}
	response, err := (&http.Client{Timeout: 12 * time.Second}).Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode >= 200 && response.StatusCode < 300 {
		return nil
	}
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 2048))
	return fmt.Errorf("support provider returned %s: %s", response.Status, strings.TrimSpace(string(responseBody)))
}
