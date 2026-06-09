package httpapi

import "net/http"

func DBCheck(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusOK, map[string]string{"database":"not_connected"})
}
