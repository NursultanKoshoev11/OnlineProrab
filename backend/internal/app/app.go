package app

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
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
	observability.Configure(os.Getenv("APP_ENV"))
	cfg, cfgErr := config.Load()
	if cfgErr != nil {
		slog.Error("configuration_load_failed", "error", cfgErr)
		os.Exit(1)
	}
	observability.Configure(cfg.Env)
	if err := cfg.Validate(); err != nil {
		slog.Error("invalid_configuration", "error", err)
		os.Exit(1)
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
			slog.Error("sms_provider_initialization_failed", "provider", cfg.SMSProvider, "error", err)
			os.Exit(1)
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
			slog.Error("sms_provider_initialization_failed", "provider", cfg.SMSProvider, "error", err)
			os.Exit(1)
		}
		smsSender = sender
	}
	if cfg.IsProductionLike() && smsSender == nil && !allowsNoSMSProvider(cfg) {
		slog.Error("sms_provider_missing")
		os.Exit(1)
	}

	var fileStore storage.ObjectStore
	var storageErr error
	if cfg.StorageDriver == "s3" {
		fileStore, storageErr = storage.NewS3(context.Background(), storage.S3Options{
			Region:               cfg.S3Region,
			Bucket:               cfg.S3Bucket,
			DeletionLedgerBucket: cfg.S3DeletionLedgerBucket,
		})
	} else {
		fileStore, storageErr = storage.NewLocal(cfg.UploadDir)
	}
	if storageErr != nil {
		slog.Error("file_storage_initialization_failed", "error", storageErr)
		os.Exit(1)
	}

	rootCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	db := bootstrap.OpenDatabase(rootCtx, cfg)
	defer db.Close()

	migrationCtx, migrationCancel := context.WithTimeout(rootCtx, 60*time.Second)
	if err := db.ApplyMigrations(migrationCtx); err != nil {
		migrationCancel()
		slog.Error("database_migration_failed", "error", err)
		os.Exit(1)
	}
	migrationCancel()

	httpapi.SetState(cfg, db, smsSender, fileStore)
	deletionWorkerDone := make(chan struct{})
	go func() {
		defer close(deletionWorkerDone)
		storage.RunDeletionWorker(rootCtx, db.Pool, fileStore)
	}()
	authPrunerDone := make(chan struct{})
	go func() {
		defer close(authPrunerDone)
		httpapi.RunAuthHistoryPruner(rootCtx)
	}()
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
	<-deletionWorkerDone
	<-authPrunerDone
	slog.Info("api_stopped")
}

func allowsNoSMSProvider(cfg config.Config) bool {
	if cfg.IsStaging() {
		return cfg.StagingTestSMSPhone != "" && cfg.StagingTestSMSCode != ""
	}
	return cfg.IsProduction() && cfg.ReviewOnlyMode
}
