package httpapi

import "net/http"

func Ready(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if !readyCheck() {
		JSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready"})
		return
	}
	JSON(w, http.StatusOK, map[string]string{"status": "ready"})
}
