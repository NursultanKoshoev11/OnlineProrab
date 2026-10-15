package storage

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func newTestS3Store(t *testing.T, server *httptest.Server) *S3Store {
	t.Helper()
	client := s3.NewFromConfig(aws.Config{
		Region:      "us-east-1",
		Credentials: credentials.NewStaticCredentialsProvider("test-access-key", "test-secret-key", ""),
		HTTPClient:  server.Client(),
	}, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(server.URL)
		options.UsePathStyle = true
	})
	return &S3Store{client: client, bucket: "stroy-test", deletionLedgerBucket: "stroy-deletion-ledger-test"}
}

func TestMultipartUploadPlanCoversAWSSizeLimit(t *testing.T) {
	partSize, partCount, err := multipartUploadPlan(s3SinglePutMaximumBytes + 1)
	if err != nil {
		t.Fatalf("plan multipart upload: %v", err)
	}
	if partSize < s3MultipartMinimumPartBytes || partCount < 2 || partCount > int32(s3MultipartMaximumParts) {
		t.Fatalf("invalid multipart plan: part_size=%d part_count=%d", partSize, partCount)
	}

	partSize, partCount, err = multipartUploadPlan(s3MultipartMaximumObjectBytes)
	if err != nil {
		t.Fatalf("plan maximum S3 object: %v", err)
	}
	if partSize > s3MultipartMaximumPartBytes || partCount != int32(s3MultipartMaximumParts) {
		t.Fatalf("maximum-object plan exceeds S3 limits: part_size=%d part_count=%d", partSize, partCount)
	}

	if _, _, err := multipartUploadPlan(s3MultipartMaximumObjectBytes + 1); err == nil {
		t.Fatal("expected objects beyond the S3 multipart limit to be rejected")
	}
}

func TestS3StoreMultipartUploadCompletesKnownSizeStream(t *testing.T) {
	var partBody []byte
	var completed bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Query().Has("uploads"):
			_, _ = io.WriteString(w, "<InitiateMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Bucket>stroy-test</Bucket><Key>project/large.bin</Key><UploadId>upload-123</UploadId></InitiateMultipartUploadResult>")
		case r.Method == http.MethodPut && r.URL.Query().Get("uploadId") == "upload-123":
			if got := r.URL.Query().Get("partNumber"); got != "1" {
				t.Errorf("unexpected multipart part number %q", got)
			}
			if got := r.Header.Get("X-Amz-Content-Sha256"); got != "UNSIGNED-PAYLOAD" {
				t.Errorf("unseekable multipart body should use the TLS-protected unsigned payload signature, got %q", got)
			}
			partBody, _ = io.ReadAll(r.Body)
			w.Header().Set("ETag", "\"part-etag\"")
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && r.URL.Query().Get("uploadId") == "upload-123":
			payload, _ := io.ReadAll(r.Body)
			if !bytes.Contains(payload, []byte("<PartNumber>1</PartNumber>")) || !bytes.Contains(payload, []byte("part-etag")) {
				t.Errorf("multipart completion omitted uploaded part metadata: %s", payload)
			}
			completed = true
			_, _ = io.WriteString(w, "<CompleteMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Bucket>stroy-test</Bucket><Key>project/large.bin</Key><ETag>\"object-etag\"</ETag></CompleteMultipartUploadResult>")
		default:
			t.Errorf("unexpected multipart request %s %s", r.Method, r.URL.String())
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	store := newTestS3Store(t, server)
	const content = "streamed large object"
	if err := store.putStream(context.Background(), "project/large.bin", strings.NewReader(content), int64(len(content)), "application/octet-stream", 1); err != nil {
		t.Fatalf("multipart upload failed: %v", err)
	}
	if string(partBody) != content {
		t.Fatalf("multipart body = %q, want %q", partBody, content)
	}
	if !completed {
		t.Fatal("multipart upload did not complete")
	}
}

func TestS3StoreMultipartUploadAbortsAfterPartFailure(t *testing.T) {
	var aborted bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Query().Has("uploads"):
			_, _ = io.WriteString(w, "<InitiateMultipartUploadResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Bucket>stroy-test</Bucket><Key>project/large.bin</Key><UploadId>upload-123</UploadId></InitiateMultipartUploadResult>")
		case r.Method == http.MethodPut && r.URL.Query().Get("uploadId") == "upload-123":
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = io.WriteString(w, "<Error><Code>InternalError</Code><Message>temporary failure</Message></Error>")
		case r.Method == http.MethodDelete && r.URL.Query().Get("uploadId") == "upload-123":
			aborted = true
			w.WriteHeader(http.StatusNoContent)
		default:
			t.Errorf("unexpected multipart request %s %s", r.Method, r.URL.String())
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	store := newTestS3Store(t, server)
	err := store.putStream(context.Background(), "project/large.bin", strings.NewReader("large"), 5, "application/octet-stream", 1)
	if err == nil {
		t.Fatal("expected multipart part failure")
	}
	if !aborted {
		t.Fatal("failed multipart upload was not aborted")
	}
}

func TestLocalStoreRoundTripAndTraversalRejection(t *testing.T) {
	store, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local store: %v", err)
	}
	if err := store.Check(context.Background()); err != nil {
		t.Fatalf("local storage health check failed: %v", err)
	}
	content := []byte("private file contents")
	if err := store.Put(context.Background(), "project/2026/receipt.pdf", bytes.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put local object: %v", err)
	}

	object, err := store.Get(context.Background(), "project/2026/receipt.pdf")
	if err != nil {
		t.Fatalf("get local object: %v", err)
	}
	defer object.Body.Close()
	if object.Size != int64(len(content)) {
		t.Fatalf("expected object size %d, got %d", len(content), object.Size)
	}
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read local object: %v", err)
	}
	if !bytes.Equal(actual, content) {
		t.Fatalf("unexpected local object content %q", actual)
	}
	if err := object.Body.Close(); err != nil {
		t.Fatalf("close local object: %v", err)
	}

	for _, key := range []string{"../secret", "project/../secret", "/absolute/key", `project\secret`, "project//secret"} {
		if err := store.Delete(context.Background(), key); err == nil {
			t.Errorf("expected invalid key %q to be rejected", key)
		}
	}
	if err := store.Delete(context.Background(), "project/2026/receipt.pdf"); err != nil {
		t.Fatalf("delete local object: %v", err)
	}
	if err := store.Delete(context.Background(), "project/2026/receipt.pdf"); err != nil {
		t.Fatalf("repeated local deletion should be idempotent: %v", err)
	}
}

func TestLocalStoreRequiresExactObjectSize(t *testing.T) {
	store, err := NewLocal(t.TempDir())
	if err != nil {
		t.Fatalf("create local store: %v", err)
	}
	if err := store.Put(context.Background(), "project/file.pdf", strings.NewReader("short"), 10, "application/pdf"); err == nil {
		t.Fatal("expected short object body to be rejected")
	}
	if _, err := os.Stat(filepath.Join(store.root, "project", "file.pdf")); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("failed upload must not leave a partial object, got %v", err)
	}
}

func TestS3StoreUsesPrivateBucketAndSupportsObjectOperations(t *testing.T) {
	var storedBody []byte
	tombstoneRecorded := false
	ledgerHealthcheckWritten := false
	ledgerHealthcheckDeleted := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead {
			if r.URL.Path != "/stroy-test" && r.URL.Path != "/stroy-deletion-ledger-test" {
				t.Errorf("unexpected S3 health-check path %q", r.URL.Path)
			}
		} else if r.Method == http.MethodGet && r.URL.Query().Has("location") {
			if strings.TrimSuffix(r.URL.Path, "/") != "/stroy-deletion-ledger-test" {
				t.Errorf("unexpected S3 deletion-ledger health-check path %q", r.URL.Path)
			}
		} else if r.Method == http.MethodPut && r.URL.Path == "/stroy-deletion-ledger-test/"+s3DeletionLedgerHealthcheckKey {
			ledgerHealthcheckWritten = true
			if got := r.Header.Get("Content-Type"); got != "application/json" {
				t.Errorf("unexpected deletion-ledger health-check content type %q", got)
			}
			body, err := io.ReadAll(r.Body)
			if err != nil {
				t.Errorf("read deletion-ledger health-check body: %v", err)
			}
			if got := string(body); got != "{\"status\":\"ok\"}\n" {
				t.Errorf("unexpected deletion-ledger health-check body %q", got)
			}
		} else if r.Method == http.MethodPut && strings.HasPrefix(r.URL.Path, "/stroy-deletion-ledger-test/tombstones/") {
			tombstoneRecorded = true
			if got := r.Header.Get("Content-Type"); got != "application/json" {
				t.Errorf("unexpected deletion tombstone content type %q", got)
			}
			if _, err := io.Copy(io.Discard, r.Body); err != nil {
				t.Errorf("read deletion tombstone: %v", err)
			}
		} else if r.URL.Path != "/stroy-test/project/2026/receipt.pdf" &&
			r.URL.Path != "/stroy-deletion-ledger-test/"+s3DeletionLedgerHealthcheckKey {
			t.Errorf("unexpected S3 request path %q", r.URL.Path)
		}
		if r.Header.Get("Authorization") == "" {
			t.Error("S3 request is not signed")
		}
		switch r.Method {
		case http.MethodPut:
			if strings.HasPrefix(r.URL.Path, "/stroy-test/") {
				if got := r.Header.Get("Content-Type"); got != "application/pdf" {
					t.Errorf("unexpected upload content type %q", got)
				}
				var err error
				storedBody, err = io.ReadAll(r.Body)
				if err != nil {
					t.Errorf("read upload body: %v", err)
				}
			}
			w.Header().Set("ETag", `"etag"`)
			w.WriteHeader(http.StatusOK)
		case http.MethodGet:
			if r.URL.Query().Has("location") {
				_, _ = w.Write([]byte(`<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/">us-east-1</LocationConstraint>`))
				return
			}
			w.Header().Set("Content-Length", strconv.Itoa(len(storedBody)))
			w.Header().Set("Content-Type", "application/pdf")
			_, _ = w.Write(storedBody)
		case http.MethodDelete:
			if r.URL.Path == "/stroy-deletion-ledger-test/"+s3DeletionLedgerHealthcheckKey {
				if !ledgerHealthcheckWritten {
					t.Error("S3 deletion-ledger health check was removed before being written")
				}
				ledgerHealthcheckDeleted = true
				w.WriteHeader(http.StatusNoContent)
				return
			}
			if !tombstoneRecorded {
				t.Error("S3 object deletion happened before its tombstone was recorded")
			}
			w.WriteHeader(http.StatusNoContent)
		case http.MethodHead:
			w.WriteHeader(http.StatusOK)
		default:
			t.Errorf("unexpected S3 method %q", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	store := newTestS3Store(t, server)
	if err := store.Check(context.Background()); err != nil {
		t.Fatalf("S3 health check failed: %v", err)
	}
	if !ledgerHealthcheckWritten || !ledgerHealthcheckDeleted {
		t.Fatalf("S3 health check must verify and clean the deletion-ledger canary: wrote=%t deleted=%t", ledgerHealthcheckWritten, ledgerHealthcheckDeleted)
	}

	content := []byte("private S3 object")
	key := "project/2026/receipt.pdf"
	if err := store.Put(context.Background(), key, bytes.NewReader(content), int64(len(content)), "application/pdf"); err != nil {
		t.Fatalf("put S3 object: %v", err)
	}
	if !bytes.Equal(storedBody, content) {
		t.Fatalf("unexpected S3 upload body %q", storedBody)
	}

	object, err := store.Get(context.Background(), key)
	if err != nil {
		t.Fatalf("get S3 object: %v", err)
	}
	defer object.Body.Close()
	actual, err := io.ReadAll(object.Body)
	if err != nil {
		t.Fatalf("read S3 object body: %v", err)
	}
	if !bytes.Equal(actual, content) || object.Size != int64(len(content)) {
		t.Fatalf("unexpected S3 object: size=%d body=%q", object.Size, actual)
	}
	if err := store.Delete(context.Background(), key); err != nil {
		t.Fatalf("delete S3 object: %v", err)
	}
}

func TestS3StoreCheckFailsWhenDeletionLedgerWriteIsDenied(t *testing.T) {
	ledgerHealthcheckPath := "/stroy-deletion-ledger-test/" + s3DeletionLedgerHealthcheckKey
	ledgerWriteAttempted := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodHead && r.URL.Path == "/stroy-test":
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodGet && r.URL.Query().Has("location") && strings.TrimSuffix(r.URL.Path, "/") == "/stroy-deletion-ledger-test":
			_, _ = io.WriteString(w, `<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/">us-east-1</LocationConstraint>`)
		case r.Method == http.MethodPut && r.URL.Path == ledgerHealthcheckPath:
			ledgerWriteAttempted = true
			w.WriteHeader(http.StatusForbidden)
			_, _ = io.WriteString(w, `<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>`)
		default:
			t.Errorf("unexpected S3 health-check request %s %s", r.Method, r.URL.String())
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	store := newTestS3Store(t, server)
	err := store.Check(context.Background())
	if err == nil || !strings.Contains(err.Error(), "deletion ledger write access") {
		t.Fatalf("expected a ledger-write permission error, got %v", err)
	}
	if !ledgerWriteAttempted {
		t.Fatal("S3 readiness did not test deletion-ledger write access")
	}
}

func TestS3StoreMapsNotFoundToFilesystemNotExist(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()
	store := newTestS3Store(t, server)
	if _, err := store.Get(context.Background(), "project/missing.pdf"); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("expected missing object to map to fs.ErrNotExist, got %v", err)
	}
}

func TestS3DeletionJournalRecordsAccountAndObjectTombstones(t *testing.T) {
	objects := map[string][]byte{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("unexpected S3 tombstone method %q", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.Header.Get("Authorization") == "" {
			t.Error("S3 tombstone request is not signed")
		}
		if got := r.Header.Get("Content-Type"); got != "application/json" {
			t.Errorf("unexpected tombstone content type %q", got)
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("read tombstone: %v", err)
		}
		objects[r.URL.Path] = body
		w.Header().Set("ETag", `"etag"`)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	store := newTestS3Store(t, server)
	userID := "7cbcf034-8122-4d2d-92fd-f704dcdf8752"
	if err := store.RecordAccountDeletion(context.Background(), userID); err != nil {
		t.Fatalf("record account deletion tombstone: %v", err)
	}
	storagePath := "project/2026/receipt.pdf"
	if err := store.RecordObjectDeletion(context.Background(), storagePath); err != nil {
		t.Fatalf("record object deletion tombstone: %v", err)
	}

	var account deletionTombstone
	if err := json.Unmarshal(objects["/stroy-deletion-ledger-test/tombstones/accounts/"+userID+".json"], &account); err != nil {
		t.Fatalf("decode account tombstone: %v", err)
	}
	if account.Version != 1 || account.Kind != "account" || account.UserID != userID || account.CreatedAt.IsZero() {
		t.Fatalf("unexpected account tombstone: %+v", account)
	}

	digest := sha256.Sum256([]byte(storagePath))
	objectKey := "/stroy-deletion-ledger-test/tombstones/objects/" + hex.EncodeToString(digest[:]) + ".json"
	var object deletionTombstone
	if err := json.Unmarshal(objects[objectKey], &object); err != nil {
		t.Fatalf("decode object tombstone: %v", err)
	}
	if object.Version != 1 || object.Kind != "object" || object.StoragePath != storagePath || object.CreatedAt.IsZero() {
		t.Fatalf("unexpected object tombstone: %+v", object)
	}
}

func TestS3DeletionJournalRejectsInvalidIdentifiersAndKeys(t *testing.T) {
	store := &S3Store{deletionLedgerBucket: "stroy-deletion-ledger-test"}
	if err := store.RecordAccountDeletion(context.Background(), "../../other-account"); err == nil {
		t.Fatal("expected invalid account identifier to be rejected")
	}
	if err := store.RecordObjectDeletion(context.Background(), "../other-user/file.pdf"); err == nil {
		t.Fatal("expected unsafe storage key to be rejected")
	}
}
