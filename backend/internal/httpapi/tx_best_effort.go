package httpapi

import (
	"context"
	"log/slog"

	"github.com/jackc/pgx/v5"
)

// bestEffortTxExec runs a non-critical statement (audit log, housekeeping)
// inside an open transaction without letting its failure poison the
// transaction. In PostgreSQL any failed statement aborts the whole
// transaction, so ignoring the error is not enough: the following
// statements and Commit would fail. A savepoint isolates the statement.
func bestEffortTxExec(ctx context.Context, tx pgx.Tx, label, sql string, args ...any) {
	nested, err := tx.Begin(ctx)
	if err != nil {
		slog.Error("best_effort_savepoint_failed", "operation", label, "error", err)
		return
	}
	if _, err := nested.Exec(ctx, sql, args...); err != nil {
		slog.Error("best_effort_statement_failed", "operation", label, "error", err)
		if rollbackErr := nested.Rollback(ctx); rollbackErr != nil {
			slog.Error("best_effort_savepoint_rollback_failed", "operation", label, "error", rollbackErr)
		}
		return
	}
	if err := nested.Commit(ctx); err != nil {
		slog.Error("best_effort_savepoint_release_failed", "operation", label, "error", err)
	}
}
