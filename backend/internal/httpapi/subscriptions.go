package httpapi

import "net/http"

func ListPlans(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"plans": []map[string]any{
			{"id": "free", "name": "Free", "price_kgs": 0, "max_projects": 1},
			{"id": "pro", "name": "Pro", "price_kgs": 990, "max_projects": 5},
			{"id": "business", "name": "Business", "price_kgs": 2990, "max_projects": 25},
		},
	})
}

func SubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"user_id": userIDFromContext(r.Context()),
		"plan":    "free",
		"status":  "active",
	})
}
