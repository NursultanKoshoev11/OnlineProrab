package bootstrap

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
)

func TestOpenWithRetryWaitsForDatabase(t *testing.T) {
	calls := 0
	want := &database.DB{}
	db, err := openWithRetry(context.Background(), 5, time.Millisecond, func(context.Context) (*database.DB, error) {
		calls++
		if calls < 3 {
			return nil, errors.New("connection refused")
		}
		return want, nil
	})
	if err != nil || db != want || calls != 3 {
		t.Fatalf("got db=%v err=%v after %d calls, want success on the third", db, err, calls)
	}
}

func TestOpenWithRetryGivesUp(t *testing.T) {
	calls := 0
	_, err := openWithRetry(context.Background(), 3, time.Millisecond, func(context.Context) (*database.DB, error) {
		calls++
		return nil, errors.New("connection refused")
	})
	if err == nil || calls != 3 {
		t.Fatalf("expected failure after 3 attempts, got err=%v calls=%d", err, calls)
	}
}
