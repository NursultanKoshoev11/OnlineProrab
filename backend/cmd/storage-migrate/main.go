package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
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
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load configuration: %v", err)
	}
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
	objectStore, err := storage.NewS3(ctx, storage.S3Options{
		Region: cfg.S3Region,
		Bucket: cfg.S3Bucket,
	})
	if err != nil {
		log.Fatalf("configure object storage: %v", err)
	}

	source, target := storage.ObjectStore(localStore), storage.ObjectStore(objectStore)
	if *direction == "s3-to-local" {
		source, target = objectStore, localStore
	}
	if err := migrateActiveFiles(ctx, db, source, target, cfg.MaxUploadBytes); err != nil {
		log.Fatalf("storage migration failed: %v", err)
	}
}

func migrateActiveFiles(ctx context.Context, db *database.DB, source, target storage.ObjectStore, maxBytes int64) error {
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
		if size < 0 || size > maxBytes {
			return fmt.Errorf("active file is outside the configured size limit")
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

	temporary, err := os.CreateTemp("", ".stroy-storage-migration-*")
	if err != nil {
		_ = object.Body.Close()
		return fmt.Errorf("create temporary copy: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	defer temporary.Close()

	sourceHash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(temporary, sourceHash), io.LimitReader(object.Body, expectedSize+1))
	closeErr := object.Body.Close()
	if copyErr != nil {
		return fmt.Errorf("copy source object: %w", copyErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close source object: %w", closeErr)
	}
	if written != expectedSize {
		return fmt.Errorf("source object bytes do not match database metadata")
	}
	if err := temporary.Sync(); err != nil {
		return fmt.Errorf("sync temporary copy: %w", err)
	}
	sourceDigest := hex.EncodeToString(sourceHash.Sum(nil))

	if _, err := temporary.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind temporary copy: %w", err)
	}
	if err := target.Put(ctx, key, temporary, expectedSize, contentType); err != nil {
		return fmt.Errorf("write destination object: %w", err)
	}
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

func hashObject(object storage.Object, expectedSize int64) (string, int64, error) {
	if object.Body == nil || object.Size != expectedSize {
		if object.Body != nil {
			_ = object.Body.Close()
		}
		return "", 0, fmt.Errorf("object size does not match database metadata")
	}
	defer object.Body.Close()
	hash := sha256.New()
	written, err := io.Copy(hash, io.LimitReader(object.Body, expectedSize+1))
	if err != nil {
		return "", written, err
	}
	if written != expectedSize {
		return "", written, fmt.Errorf("object bytes do not match database metadata")
	}
	return hex.EncodeToString(hash.Sum(nil)), written, nil
}
