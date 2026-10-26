package observability

import (
	"bytes"
	"encoding/json"
	"log"
	"log/slog"
	"strings"
	"testing"
)

func TestNewHandlerUsesJSONOutsideDevelopment(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(NewHandler("staging", &output))
	logger.Info("service_started", "environment", "staging")

	var record map[string]any
	if err := json.Unmarshal(output.Bytes(), &record); err != nil {
		t.Fatalf("expected valid JSON log record, got %q: %v", output.String(), err)
	}
	if record["msg"] != "service_started" || record["environment"] != "staging" {
		t.Fatalf("unexpected JSON log record: %#v", record)
	}
}

func TestNewHandlerKeepsDevelopmentLogsReadable(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(NewHandler("development", &output))
	logger.Info("service_started", "environment", "development")

	if got := output.String(); !strings.Contains(got, "msg=service_started") || !strings.Contains(got, "environment=development") {
		t.Fatalf("expected readable text log, got %q", got)
	}
}

func TestConfigureRoutesStandardLogThroughJSONHandler(t *testing.T) {
	var output bytes.Buffer
	previousLogger := slog.Default()
	previousFlags := log.Flags()
	slog.SetDefault(slog.New(NewHandler("production", &output)))
	log.SetFlags(0)
	t.Cleanup(func() {
		slog.SetDefault(previousLogger)
		log.SetFlags(previousFlags)
	})

	log.Print("legacy_log_event")

	var record map[string]any
	if err := json.Unmarshal(output.Bytes(), &record); err != nil {
		t.Fatalf("expected standard log output to be JSON, got %q: %v", output.String(), err)
	}
	if record["msg"] != "legacy_log_event" || record["level"] != "INFO" {
		t.Fatalf("unexpected standard log record: %#v", record)
	}
}
