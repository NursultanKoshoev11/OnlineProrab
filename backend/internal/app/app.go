package app

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/bootstrap"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
)

func Run() {
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}

	db := bootstrap.OpenDatabase(context.Background(), cfg)
	defer db.Close()

	if err := db.EnsureSchema(context.Background()); err != nil {
		log.Fatalf("failed to ensure database schema: %v", err)
	}

	httpapi.SetState(cfg, db)
	httpapi.SetCORSAllowedOrigins(cfg.CORSAllowedOrigins)
	httpapi.SetReadyCheck(func() bool {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		return db.Ping(ctx) == nil
	})

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.NewRouter(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("onlineprorab api starting env=%s addr=%s", cfg.Env, cfg.HTTPAddr)
	log.Fatal(server.ListenAndServe())
}
