package httpapi

import "net/http"

func NewRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", Health)
	mux.HandleFunc("/ready", Ready)
	mux.HandleFunc("/api/v1/projects", Projects)
	mux.HandleFunc("/api/v1/cost-items", CostItems)
	mux.HandleFunc("/api/v1/daily-reports", DailyReports)
	mux.HandleFunc("/api/v1/files", Files)
	mux.HandleFunc("/api/v1/auth/sms/request", RequestSMSCode)