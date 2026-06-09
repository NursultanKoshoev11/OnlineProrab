package httpapi

import "net/http"

func Ready(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusOK, map[string]string{"status":"ready"})
}
