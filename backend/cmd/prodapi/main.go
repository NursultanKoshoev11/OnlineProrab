package main

import (
	"log"
	"net/http"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load configuration: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", httpapi.Health)
	mux.HandleFunc("/ready", httpapi.Ready)
	log.Fatal(http.ListenAndServe(cfg.HTTPAddr, mux))
}
