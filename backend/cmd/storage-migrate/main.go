package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"hash"
	"io"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/config"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/database"
	"github.com/NursultanKoshoev11/OnlineProrab/backend/internal/storage"
)

func main() {
	direction := flag.String("direction", "local-to-s3", "copy direction: local-to-s3 or s3-to-local")
	flag.Parse()
	if flag.NArg() != 0 {
		log.Fatal("unexpected positional arguments")
	}
	if *direction != "local-to-s3" && *direction != "s3-to-local" {
		log.Fatal("-direction must be local-to-s3 or s3-to-local")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}
	if cfg.StorageDriver != "s3" {
		log.Fatal("STORAGE_DRIVER=s3 is required to run the storage migration tool")
	}

	db, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()

	localStore, err := storage.NewLocal(cfg.UploadDir)
	if err != nil {
		log.Fatalf("configure local storage: %v", err)
	}
	objectStore, err := storage.NewS3(ctx, migrationS3Options(cfg))
	if err != nil {
		log.Fatalf("configure object storage: %v", err)
	}

	source, target := storage.ObjectStore(localStore), storage.ObjectStore(objectStore)
	if *direction == "s3-to-local" {
		source, target = objectStore, localStore
	}
	if err := migrateActiveFiles(ctx, db, source, target); err != nil {
		log.Fatalf("storage migration failed: %v", err)
	}
}

func migrationS3Options(cfg config.Config) storage.S3Options {
	return storage.S3Options{
		Region:               cfg.S3Region,
		Bucket:               cfg.S3Bucket,
		DeletionLedgerBucket: cfg.S3DeletionLedgerBucket,
	}
}

func migrateActiveFiles(ctx context.Context, db *database.DB, source, target storage.ObjectStore) error {
	rows, err := db.Pool.Query(ctx, `
		SELECT storage_path, min(size_bytes), min(content_type),
		       count(DISTINCT size_bytes), count(DISTINCT content_type)
		FROM files
		WHERE deleted_at IS NULL
		GROUP BY storage_path
		ORDER BY storage_path
	`)
	if err != nil {
		return fmt.Errorf("list active file objects: %w", err)
	}
	defer rows.Close()

	var migrated int64
	for rows.Next() {
		var key string
		var size int64
		var contentType string
		var sizeVariants int64
		var contentTypeVariants int64
		if err := rows.Scan(&key, &size, &contentType, &sizeVariants, &contentTypeVariants); err != nil {
			return fmt.Errorf("read active file metadata: %w", err)
		}
		if strings.TrimSpace(key) == "" || sizeVariants != 1 || contentTypeVariants != 1 {
			return fmt.Errorf("active file metadata is inconsistent")
		}
		if size < 0 {
			return fmt.Errorf("active file has a negative size")
		}
		if err := copyAndVerify(ctx, source, target, key, size, contentType); err != nil {
			return fmt.Errorf("copy active file: %w", err)
		}
		migrated++
		log.Printf("verified active storage object count=%d", migrated)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate active file metadata: %w", err)
	}
	log.Printf("storage migration complete active_objects=%d", migrated)
	return nil
}

func copyAndVerify(ctx context.Context, source, target storage.ObjectStore, key string, expectedSize int64, contentType string) error {
	if expectedSize < 0 {
		return fmt.Errorf("object has a negative size")
	}
	streamingTarget, ok := target.(storage.StreamingObjectStore)
	if !ok {
		return fmt.Errorf("destination storage does not support streaming migration")
	}

	object, err := source.Get(ctx, key)
	if err != nil {
		return fmt.Errorf("read source object: %w", err)
	}
	if object.Body == nil || object.Size != expectedSize {
		if object.Body != nil {
			_ = object.Body.Close()
		}
		return fmt.Errorf("source object size does not match database metadata")
	}

	sourceHash := sha256.New()
	hashedSource := &hashingReader{source: object.Body, hash: sourceHash}
	if err := streamingTarget.PutStream(ctx, key, hashedSource, expectedSize, contentType); err != nil {
		_ = object.Body.Close()
		return fmt.Errorf("write destination object: %w", err)
	}
	if err := object.Body.Close(); err != nil {
		return fmt.Errorf("close source object: %w", err)
	}
	if hashedSource.bytesRead != expectedSize {
		return fmt.Errorf("source object bytes do not match database metadata")
	}
	sourceDigest := hex.EncodeToString(sourceHash.Sum(nil))

	verified, err := target.Get(ctx, key)
	if err != nil {
		return fmt.Errorf("read back destination object: %w", err)
	}
	destinationDigest, destinationSize, err := hashObject(verified, expectedSize)
	if err != nil {
		return fmt.Errorf("verify destination object: %w", err)
	}
	if destinationSize != expectedSize || destinationDigest != sourceDigest {
		return fmt.Errorf("destination object verification failed")
	}
	return nil
}

type hashingReader struct {
	source    io.Reader
	hash      hash.Hash
	bytesRead int64
}

func (r *hashingReader) Read(buffer []byte) (int, error) {
	count, err := r.source.Read(buffer)
	if count > 0 {
		_, _ = r.hash.Write(buffer[:count])
		r.bytesRead += int64(count)
	}
	return count, err
}

func hashObject(object storage.Object, expectedSize int64) (string, int64, error) {
	if object.Body == nil || object.Size != expectedSize {
		if object.Body != nil {
			_ = object.Body.Close()
		}
		return "", 0, fmt.Errorf("object size does not match database metadata")
	}
	defer object.Body.Close()
	hash := sha256.New()
	written, err := io.Copy(hash, object.Body)
	if err != nil {
		return "", written, err
	}
	if written != expectedSize {
		return "", written, fmt.Errorf("object bytes do not match database metadata")
	}
	return hex.EncodeToString(hash.Sum(nil)), written, nil
}
