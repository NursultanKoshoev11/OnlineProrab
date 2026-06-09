package httpapi

import "net/http"

func RequestSMSCode(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusAccepted, map[string]string{"status": "code_requested"})
}

func VerifySMSCode(w http.ResponseWriter, r *http.Request) {
	JSON(w, http.StatusOK, map[string]string{"status": "verified"})
}
