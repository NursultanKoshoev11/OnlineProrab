package httpapi

import "net/http"

func Ready(w http.ResponseWriter, r *http.Request) {
    if !readyCheck() {
        JSON(w, http.StatusServiceUnavailable, map[string]string{"status":"not_ready"})
        return
    }
    JSON(w, http.StatusOK, map[string]string{"status":"ready"})
}
