package httpapi

import "net/http"

type ProjectDTO struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Currency string `json:"currency"`
}

func Projects(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		JSON(w, http.StatusOK, []ProjectDTO{})
		return
	}
	if r.Method == http.MethodPost {
		JSON(w, http.StatusCreated, ProjectDTO{ID: "demo", Name: "Demo Project", Currency: "KGS"