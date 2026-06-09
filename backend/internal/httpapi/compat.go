package httpapi

func writeJSON(w http.ResponseWriter, status int, value any) {
	JSON(w, status, value)
}
