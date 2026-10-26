package storage

import (
	"context"
	"fmt"
	"log"
	"math"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	deletionPollInterval = 5 * time.Second
	deletionBatchSize    = 10
	deletionLease        = 5 * time.Minute
	deletionTimeout      = 20 * time.Second
	deletionRetryBase    = 5 * time.Second
	deletionRetryMax     = time.Hour
)

type pendingDeletion struct {
	id          int64
	storagePath string
	attempts    int
}

// RunDeletionWorker retries object removals recorded in the database outbox.
// It returns when ctx is cancelled.
func RunDeletionWorker(ctx context.Context, pool *pgxpool.Pool, store ObjectStore) {
	if pool == nil || store == nil {
		log.Printf("file deletion worker disabled: database or object storage is unavailable")
		return
	}

	processAvailableDeletions(ctx, pool, store)
	ticker := time.NewTicker(deletionPollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			processAvailableDeletions(ctx, pool, store)
		}
	}
}

func processAvailableDeletions(ctx context.Context, pool *pgxpool.Pool, store ObjectStore) {
	for ctx.Err() == nil && processDeletionBatch(ctx, pool, store) {
	}
}

func processDeletionBatch(ctx context.Context, pool *pgxpool.Pool, store ObjectStore) bool {
	items, err := claimPendingDeletions(ctx, pool)
	if err != nil {
		if ctx.Err() == nil {
			log.Printf("file deletion worker failed to claim objects: %v", err)
		}
		return false
	}
	if len(items) == 0 {
		return false
	}

	var workers sync.WaitGroup
	for index, item := range items {
		if ctx.Err() != nil {
			releaseDeletionClaims(pool, items[index:])
			break
		}
		workers.Add(1)
		go func(item pendingDeletion) {
			defer workers.Done()
			deleteCtx, cancel := context.WithTimeout(ctx, deletionTimeout)
			deleteErr := store.Delete(deleteCtx, item.storagePath)
			cancel()
			if deleteErr == nil {
				if err := markDeletionComplete(pool, item.id); err != nil {
					log.Printf("file deletion worker could not mark object complete id=%d: %v", item.id, err)
				}
				return
			}
			if retryErr := rescheduleDeletion(pool, item, deleteErr); retryErr != nil {
				log.Printf("file deletion worker could not schedule retry id=%d: %v (delete: %v)", item.id, retryErr, deleteErr)
				return
			}
			log.Printf("file deletion failed id=%d attempt=%d retry_in=%s error=%v", item.id, item.attempts+1, deletionRetryDelay(item.attempts), deleteErr)
		}(item)
	}
	workers.Wait()
	return len(items) == deletionBatchSize && ctx.Err() == nil
}

func releaseDeletionClaims(pool *pgxpool.Pool, items []pendingDeletion) {
	if len(items) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for _, item := range items {
		if _, err := pool.Exec(ctx, `
			UPDATE file_storage_deletions
			SET locked_until = NULL, available_at = LEAST(available_at, now())
			WHERE id = $1
		`, item.id); err != nil {
			log.Printf("file deletion worker could not release object claim id=%d: %v", item.id, err)
		}
	}
}

func claimPendingDeletions(ctx context.Context, pool *pgxpool.Pool) ([]pendingDeletion, error) {
	claimCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	tx, err := pool.Begin(claimCtx)
	if err != nil {
		return nil, fmt.Errorf("begin claim transaction: %w", err)
	}
	defer tx.Rollback(claimCtx)
	rows, err := tx.Query(claimCtx, `
		WITH candidates AS (
			SELECT id
			FROM file_storage_deletions
			WHERE available_at <= now()
			  AND (locked_until IS NULL OR locked_until <= now())
			ORDER BY available_at, id
			LIMIT $1
			FOR UPDATE SKIP LOCKED
		)
		UPDATE file_storage_deletions AS deletions
		SET locked_until = now() + ($2 * interval '1 second')
		FROM candidates
		WHERE deletions.id = candidates.id
		RETURNING deletions.id, deletions.storage_path, deletions.attempts
	`, deletionBatchSize, int(deletionLease.Seconds()))
	if err != nil {
		return nil, fmt.Errorf("select pending objects: %w", err)
	}
	items := make([]pendingDeletion, 0, deletionBatchSize)
	for rows.Next() {
		var item pendingDeletion
		if err := rows.Scan(&item.id, &item.storagePath, &item.attempts); err != nil {
			rows.Close()
			return nil, fmt.Errorf("read claimed object: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, fmt.Errorf("read claimed objects: %w", err)
	}
	rows.Close()
	if err := tx.Commit(claimCtx); err != nil {
		return nil, fmt.Errorf("commit claim transaction: %w", err)
	}
	return items, nil
}

func markDeletionComplete(pool *pgxpool.Pool, id int64) error {
	markCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := pool.Exec(markCtx, `
		DELETE FROM file_storage_deletions
		WHERE id = $1
	`, id)
	return err
}

func rescheduleDeletion(pool *pgxpool.Pool, item pendingDeletion, deleteErr error) error {
	updateCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	delay := deletionRetryDelay(item.attempts)
	message := deleteErr.Error()
	if len(message) > 1024 {
		message = message[:1024]
	}
	_, err := pool.Exec(updateCtx, `
		UPDATE file_storage_deletions
		SET attempts = attempts + 1,
		    available_at = now() + ($2 * interval '1 second'),
		    locked_until = NULL,
		    last_error = $3
		WHERE id = $1
	`, item.id, int(delay.Seconds()), message)
	return err
}

func deletionRetryDelay(attempts int) time.Duration {
	if attempts < 0 {
		attempts = 0
	}
	seconds := float64(deletionRetryBase) * math.Pow(2, float64(min(attempts, 10)))
	delay := time.Duration(seconds)
	if delay > deletionRetryMax {
		return deletionRetryMax
	}
	return delay
}
