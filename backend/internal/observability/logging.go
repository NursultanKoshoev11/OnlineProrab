package observability

import (
	"io"
	"log"
	"log/slog"
	"os"
	"strings"
)

const developmentEnv = "development"

// NewHandler keeps development logs readable and emits machine-readable
// records for every production-like environment.
func NewHandler(environment string, output io.Writer) slog.Handler {
	options := &slog.HandlerOptions{Level: slog.LevelInfo}
	if strings.EqualFold(strings.TrimSpace(environment), developmentEnv) {
		return slog.NewTextHandler(output, options)
	}
	return slog.NewJSONHandler(output, options)
}

// Configure sets the process-wide logger. slog.SetDefault also routes calls
// through the standard log package to the same handler.
func Configure(environment string) {
	slog.SetDefault(slog.New(NewHandler(environment, os.Stdout)))
	log.SetFlags(0)
}
