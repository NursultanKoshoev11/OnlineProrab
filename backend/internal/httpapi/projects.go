package httpapi

import "net/http"

type ProjectDTO struct {
	ID string `json:"id"`
	Name string `json:"name"`
}

func Projects(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		JSON(w, 200, []ProjectDTO{})
		return
	}
	if r.Method == http.MethodPost {
		JSON(w, 201, ProjectDTO{ID: "demo", Name: "Demo Project"})
		return
	}
	Error(w, 405, "method not allowed")
}
