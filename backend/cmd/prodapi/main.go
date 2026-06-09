package main

import (
	"log"
	"net/http"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()
	mux := http.NewServeMux()
	mux.HandleFunc("/health", httpapi.Health)
	mux.HandleFunc("/ready", httpapi.Ready)
	mux.HandleFunc("/api/v1/projects", httpapi.Projects)
	mux.HandleFunc("/api/v1/cost-items", httpapi.CostItems)
	mux.HandleFunc("/api/v1/daily-reports", httpapi.DailyReports)
	mux.HandleFunc("/api