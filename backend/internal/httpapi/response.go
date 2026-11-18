package httpapi

import (
	"encoding/json"
	"net/http"
)

type ErrorResponse struct {
	Error string `json:"error"`
	// Code is a stable machine-readable reason for errors clients act on.
	Code string `json:"code,omitempty"`
}

const subscriptionExpiredMessage = "subscription is expired; choose a paid plan"

// errorCodes maps messages that clients branch on to stable codes, so apps do
// not have to match human-readable text.
var errorCodes = map[string]string{
	subscriptionExpiredMessage: "subscription_expired",
}

func JSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	JSON(w, status, value)
}

func Error(w http.ResponseWriter, status int, message string) {
	JSON(w, status, ErrorResponse{Error: message, Code: errorCodes[message]})
}
