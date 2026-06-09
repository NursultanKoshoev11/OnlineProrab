package app

import (
    "context"
    "log"
    "net/http"

    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/bootstrap"
    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
    "github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func Run() {
    cfg := config.Load()
    db := bootstrap.OpenDatabase(context.Background(), cfg)
    defer db.Close()

    httpapi.SetReadyCheck(func() bool { return true })

    log.Println("OnlineProrab API listening", cfg.HTTPAddr)
    log.Fatal(http.ListenAndServe(cfg.HTTPAddr, httpapi.NewRouter()))
}
