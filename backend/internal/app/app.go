package app

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os/signal"
	"syscall"
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

	rootCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	db := bootstrap.OpenDatabase(rootCtx, cfg)
	defer db.Close()

	migrationCtx, migrationCancel := context.WithTimeout(rootCtx, 60*time.Second)
	if err := db.ApplyMigrations(migrationCtx); err != nil {
		migrationCancel()
		log.Fatalf("failed to apply database migrations: %v", err)
	}
	migrationCancel()

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

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("onlineprorab api starting env=%s addr=%s", cfg.Env, cfg.HTTPAddr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case <-rootCtx.Done():
		log.Printf("shutdown signal received")
	case err := <-serverErrors:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("http server stopped unexpectedly: %v", err)
		}
		stop()
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer shutdownCancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
		_ = server.Close()
	}
	log.Printf("onlineprorab api stopped")
}
