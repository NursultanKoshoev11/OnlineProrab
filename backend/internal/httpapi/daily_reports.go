package httpapi

import "net/http"

type DailyReportDTO struct {
	ID string `json:"id"`
	Summary string `json:"summary"`
}

func DailyReports(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		JSON(w, 200, []DailyReportDTO{})
		return
	}
	if r.Method == http.MethodPost {
		JSON(w, 201, DailyReportDTO{ID: "demo", Summary: "Work report"})
		return
	}
	Error(w, 405, "method not allowed")
}
