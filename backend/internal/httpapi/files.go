package httpapi

import "net/http"

func Files(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusOK, map[string]any{"items": []any{}})
}
