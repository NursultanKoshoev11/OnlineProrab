package httpapi

import "net/http"

func NewRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", Health)
	mux.HandleFunc("/ready", Ready)
	mux.HandleFunc("/api/v1/health", Health)
	mux.HandleFunc("/api/v1/ready", Ready)
	mux.HandleFunc("/api/v1/projects", Projects)
	mux.HandleFunc("/api/v1/cost-items", CostItems)
	mux.HandleFunc("/api/v1/daily-reports", DailyReports)
	return mux
}
