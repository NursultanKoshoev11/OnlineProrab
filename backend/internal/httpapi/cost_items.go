package httpapi

import "net/http"

type CostItemDTO struct {
	ID string `json:"id"`
	Title string `json:"title"`
}

func CostItems(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		JSON(w, 200, []CostItemDTO{})
		return
	}
	if r.Method == http.MethodPost {
		JSON(w, 201, CostItemDTO{ID: "demo", Title: "Material"})
		return
	}
	Error(w, 405, "method not allowed")
}
