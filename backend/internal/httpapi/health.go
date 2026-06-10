package httpapi

import "net/http"

type HealthResponse struct {
	Status  string `json:"status"`
	Service string `json:"service"`
	Version string `json:"version"`
}

func Health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	JSON(w, http.StatusOK, HealthResponse{Status: "ok", Service: "onlineprorab-api", Version: "0.1.0"})
}
