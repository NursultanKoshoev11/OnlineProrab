package storage

import (
	"context"
	"io"
	"time"
)

// ObjectStore stores private user files under opaque, application-generated keys.
type ObjectStore interface {
	Put(ctx context.Context, key string, source io.ReadSeeker, size int64, contentType string) error
	Get(ctx context.Context, key string) (Object, error)
	Delete(ctx context.Context, key string) error
}

// HealthChecker reports whether the object store can currently serve requests.
type HealthChecker interface {
	Check(ctx context.Context) error
}

// Object contains a readable object body and the metadata needed for downloads.
type Object struct {
	Body    io.ReadCloser
	Size    int64
	ModTime time.Time
}
