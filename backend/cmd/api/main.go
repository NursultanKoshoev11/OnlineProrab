package main

import (
	"log"
	"net/http"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()
	server := &http.Server{
		Addr: cfg.HTTPAddr,
		Handler: httpapi.NewRouter(),
	}
	log.Printf("OnlineProrab API listening on %s", cfg.HTTPAddr)
	if err := server.ListenAndServe(); err != nil {
