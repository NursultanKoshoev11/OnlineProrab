package main

import (
	"log"
	"net/http"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/observability"
)

func main() {
	cfg := config.Load()
	observability.Configure(cfg.Env)
	mux := http.NewServeMux()
	mux.HandleFunc("/health", httpapi.Health)
	mux.HandleFunc("/ready", httpapi.Ready)
	log.Fatal(http.ListenAndServe(cfg.HTTPAddr, mux))
}
