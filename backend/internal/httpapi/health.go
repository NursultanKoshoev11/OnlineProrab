package httpapi

import "net/http"

type HealthResponse struct {
	Status string `json:"status"`
	Service string `json:"service"`
}

func Health(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusOK, HealthResponse{Status: "ok", Service: "onlineprorab-api"})
}
