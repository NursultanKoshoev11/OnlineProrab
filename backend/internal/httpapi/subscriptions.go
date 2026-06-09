package httpapi

import "net/http"

func ListPlans(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"plans": []string{"free", "pro", "business"},
	})
}

func SubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"plan": "free",
		"status": "inactive",
	})
}
