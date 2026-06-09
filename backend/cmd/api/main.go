package main

import (
    "context"
    "log"
    "net/http"

    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func main() {
    cfg := config.Load()
    db, err := database.Open(context.Background(), cfg.DatabaseURL)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    log.Println("OnlineProrab API listening", cfg.HTTPAddr)
    log.Fatal(http.ListenAndServe(cfg.HTTPAddr