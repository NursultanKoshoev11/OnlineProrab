package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

type LocalStore struct {
	root string
}

func NewLocal(root string) (*LocalStore, error) {
	root = strings.TrimSpace(root)
	if root == "" || root == "." {
		return nil, fmt.Errorf("local storage root is required")
	}
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("resolve local storage root: %w", err)
	}
	absoluteRoot = filepath.Clean(absoluteRoot)
	if err := os.MkdirAll(absoluteRoot, 0o750); err != nil {
		return nil, fmt.Errorf("create local storage root: %w", err)
	}
	return &LocalStore{root: absoluteRoot}, nil
}

func (s *LocalStore) Check(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(s.root, ".stroy-healthcheck-*")
	if err != nil {
		return fmt.Errorf("local storage is not writable: %w", err)
	}
	name := temporary.Name()
	if err := temporary.Close(); err != nil {
		_ = os.Remove(name)
		return fmt.Errorf("close local storage health check: %w", err)
	}
	if err := os.Remove(name); err != nil {
		return fmt.Errorf("remove local storage health check: %w", err)
	}
	return nil
}

func (s *LocalStore) Put(ctx context.Context, key string, source io.ReadSeeker, size int64, _ string) error {
	if source == nil || size < 0 {
		return fmt.Errorf("invalid object body or size")
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind object body: %w", err)
	}
	return s.PutStream(ctx, key, source, size, "")
}

func (s *LocalStore) PutStream(ctx context.Context, key string, source io.Reader, size int64, _ string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	key, err := cleanKey(key)
	if err != nil {
		return err
	}
	if source == nil || size < 0 {
		return fmt.Errorf("invalid object body or size")
	}
	destination, err := s.pathFor(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o750); err != nil {
		return fmt.Errorf("create object directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(destination), ".stroy-upload-*")
	if err != nil {
		return fmt.Errorf("create temporary object: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o640); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("set object permissions: %w", err)
	}
	written, copyErr := io.CopyN(temporary, source, size)
	if copyErr != nil || written != size {
		_ = temporary.Close()
		return fmt.Errorf("copy object body: expected %d bytes, wrote %d: %w", size, written, copyErr)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("sync object body: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close object body: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, destination); err != nil {
		return fmt.Errorf("publish local object: %w", err)
	}
	return nil
}

func (s *LocalStore) Get(ctx context.Context, key string) (Object, error) {
	if err := ctx.Err(); err != nil {
		return Object{}, err
	}
	key, err := cleanKey(key)
	if err != nil {
		return Object{}, err
	}
	file, err := os.Open(filepath.Join(s.root, filepath.FromSlash(key)))
	if err != nil {
		return Object{}, err
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return Object{}, err
	}
	if !info.Mode().IsRegular() {
		_ = file.Close()
		return Object{}, fs.ErrNotExist
	}
	return Object{Body: file, Size: info.Size(), ModTime: info.ModTime()}, nil
}

func (s *LocalStore) Delete(ctx context.Context, key string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	key, err := cleanKey(key)
	if err != nil {
		return err
	}
	err = os.Remove(filepath.Join(s.root, filepath.FromSlash(key)))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	return err
}

func (s *LocalStore) pathFor(key string) (string, error) {
	destination := filepath.Clean(filepath.Join(s.root, filepath.FromSlash(key)))
	relative, err := filepath.Rel(s.root, destination)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("invalid object key")
	}
	return destination, nil
}

var _ ObjectStore = (*LocalStore)(nil)
var _ StreamingObjectStore = (*LocalStore)(nil)
