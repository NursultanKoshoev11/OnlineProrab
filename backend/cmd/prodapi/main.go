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
	api := "/api/v1/"

	mux.HandleFunc("/health", httpapi.Health)
	mux.HandleFunc("/ready", httpapi.Ready)
	mux.HandleFunc(api+"projects", httpapi.Projects)
	mux.HandleFunc