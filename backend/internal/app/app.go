package app

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/bootstrap"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/httpapi"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/observability"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/sms"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

func Run() {
	cfg := config.Load()
	observability.Configure(cfg.Env)
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}

	var smsSender httpapi.SMSSender
	if cfg.SMSProvider == config.SMSProviderTwilio {
		sender, err := sms.NewTwilioSender(sms.TwilioConfig{
			AccountSID:          cfg.TwilioAccountSID,
			APIKeySID:           cfg.TwilioAPIKeySID,
			APIKeySecret:        cfg.TwilioAPIKeySecret,
			From:                cfg.TwilioFrom,
			MessagingServiceSID: cfg.TwilioMessagingServiceSID,
		})
		if err != nil {
			log.Fatalf("failed to initialize SMS provider: %v", err)
		}
		smsSender = sender
	} else if cfg.SMSProvider == config.SMSProviderNikita {
		sender, err := sms.NewNikitaSender(sms.NikitaConfig{
			APIURL:   cfg.NikitaAPIURL,
			Login:    cfg.NikitaLogin,
			Password: cfg.NikitaPassword,
			Sender:   cfg.NikitaSender,
			TestMode: cfg.NikitaTestMode,
		})
		if err != nil {
			log.Fatalf("failed to initialize SMS provider: %v", err)
		}
		smsSender = sender
	}
	if cfg.IsProductionLike() && smsSender == nil && !cfg.ReviewOnlyMode {
		log.Fatal("SMS provider is required in staging and production unless production review-only mode is enabled")
	}

	var fileStore storage.ObjectStore
	var storageErr error
	if cfg.StorageDriver == "s3" {
		fileStore, storageErr = storage.NewS3(context.Background(), storage.S3Options{
			Region: cfg.S3Region,
			Bucket: cfg.S3Bucket,
		})
	} else {
		fileStore, storageErr = storage.NewLocal(cfg.UploadDir)
	}
	if storageErr != nil {
		log.Fatalf("failed to initialize file storage: %v", storageErr)
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

	httpapi.SetState(cfg, db, smsSender, fileStore)
	go storage.RunDeletionWorker(rootCtx, db.Pool, fileStore)
	httpapi.SetCORSAllowedOrigins(cfg.CORSAllowedOrigins)
	httpapi.SetReadyCheck(func() bool {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if db.Ping(ctx) != nil {
			return false
		}
		checker, ok := fileStore.(storage.HealthChecker)
		return ok && checker.Check(ctx) == nil
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
		slog.Info("api_starting", "environment", cfg.Env, "listen_address", cfg.HTTPAddr)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case <-rootCtx.Done():
		slog.Info("shutdown_signal_received")
	case err := <-serverErrors:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("http_server_stopped_unexpectedly", "error", err)
		}
		stop()
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer shutdownCancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful_shutdown_failed", "error", err)
		_ = server.Close()
	}
	slog.Info("api_stopped")
}
