package httpapi

import "context"

type contextKey string

const (
	userIDContextKey             contextKey = "user_id"
	sessionIDContextKey          contextKey = "session_id"
	sessionBootstrapIDContextKey contextKey = "session_bootstrap_id"
)

func withUserID(ctx context.Context, userID string) context.Context {
	return context.WithValue(ctx, userIDContextKey, userID)
}

func userIDFromContext(ctx context.Context) string {
	value, _ := ctx.Value(userIDContextKey).(string)
	return value
}

func withSessionID(ctx context.Context, sessionID string) context.Context {
	return context.WithValue(ctx, sessionIDContextKey, sessionID)
}

func sessionIDFromContext(ctx context.Context) string {
	value, _ := ctx.Value(sessionIDContextKey).(string)
	return value
}

func withSessionBootstrapID(ctx context.Context, bootstrapID string) context.Context {
	return context.WithValue(ctx, sessionBootstrapIDContextKey, bootstrapID)
}

func sessionBootstrapIDFromContext(ctx context.Context) string {
	value, _ := ctx.Value(sessionBootstrapIDContextKey).(string)
	return value
}
