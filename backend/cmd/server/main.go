package main

import (
	"log"
	"net/http"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func main() {
	cfg := config.Load()
	log.Fatal(http.ListenAndServe(cfg.HTTPAddr, httpapi.NewRouter()))
}
