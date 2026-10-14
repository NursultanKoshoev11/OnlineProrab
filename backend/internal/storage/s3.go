package storage

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

type S3Options struct {
	Region               string
	Bucket               string
	DeletionLedgerBucket string
}

type S3Store struct {
	client               *s3.Client
	bucket               string
	deletionLedgerBucket string
}

func NewS3(ctx context.Context, options S3Options) (*S3Store, error) {
	options.Region = strings.TrimSpace(options.Region)
	options.Bucket = strings.TrimSpace(options.Bucket)
	options.DeletionLedgerBucket = strings.TrimSpace(options.DeletionLedgerBucket)
	if options.Region == "" || options.Bucket == "" || options.DeletionLedgerBucket == "" {
		return nil, fmt.Errorf("S3 region, bucket, and deletion ledger bucket are required")
	}
	if options.Bucket == options.DeletionLedgerBucket {
		return nil, fmt.Errorf("S3 object and deletion ledger buckets must be different")
	}

	awsConfig, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(options.Region))
	if err != nil {
		return nil, fmt.Errorf("load S3 client configuration: %w", err)
	}
	credentialCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if _, err := awsConfig.Credentials.Retrieve(credentialCtx); err != nil {
		return nil, fmt.Errorf("S3 credentials are unavailable")
	}

	client := s3.NewFromConfig(awsConfig)
	return &S3Store{
		client:               client,
		bucket:               options.Bucket,
		deletionLedgerBucket: options.DeletionLedgerBucket,
	}, nil
}

func (s *S3Store) Put(ctx context.Context, key string, source io.ReadSeeker, size int64, contentType string) error {
	key, err := cleanKey(key)
	if err != nil {
		return err
	}
	if source == nil || size < 0 {
		return fmt.Errorf("invalid object body or size")
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("rewind object body: %w", err)
	}
	_, err = s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          source,
		ContentLength: aws.Int64(size),
		ContentType:   aws.String(contentType),
	})
	if err != nil {
		return fmt.Errorf("put S3 object: %w", err)
	}
	return nil
}

func (s *S3Store) Get(ctx context.Context, key string) (Object, error) {
	key, err := cleanKey(key)
	if err != nil {
		return Object{}, err
	}
	result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		var noSuchKey *types.NoSuchKey
		var apiError smithy.APIError
		if errors.As(err, &noSuchKey) || (errors.As(err, &apiError) && apiError.ErrorCode() == "NoSuchKey") {
			return Object{}, fs.ErrNotExist
		}
		if responseErrorStatus(err) == http.StatusNotFound {
			return Object{}, fs.ErrNotExist
		}
		return Object{}, fmt.Errorf("get S3 object: %w", err)
	}
	if result.ContentLength == nil {
		_ = result.Body.Close()
		return Object{}, fmt.Errorf("S3 response did not include object size")
	}
	object := Object{Body: result.Body, Size: *result.ContentLength}
	if result.LastModified != nil {
		object.ModTime = *result.LastModified
	}
	return object, nil
}

func (s *S3Store) Delete(ctx context.Context, key string) error {
	key, err := cleanKey(key)
	if err != nil {
		return err
	}
	if err := s.RecordObjectDeletion(ctx, key); err != nil {
		return fmt.Errorf("record S3 object deletion: %w", err)
	}
	_, err = s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("delete S3 object: %w", err)
	}
	return nil
}

func (s *S3Store) Check(ctx context.Context) error {
	_, err := s.client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(s.bucket)})
	if err != nil {
		return fmt.Errorf("check S3 bucket availability: %w", err)
	}
	_, err = s.client.GetBucketLocation(ctx, &s3.GetBucketLocationInput{Bucket: aws.String(s.deletionLedgerBucket)})
	if err != nil {
		return fmt.Errorf("check S3 deletion ledger availability: %w", err)
	}
	return nil
}

type deletionTombstone struct {
	Version     int       `json:"version"`
	Kind        string    `json:"kind"`
	UserID      string    `json:"user_id,omitempty"`
	StoragePath string    `json:"storage_path,omitempty"`
	CreatedAt   time.Time `json:"created_at_utc"`
}

var canonicalUUID = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func (s *S3Store) RecordAccountDeletion(ctx context.Context, userID string) error {
	if !canonicalUUID.MatchString(userID) {
		return fmt.Errorf("record account deletion: invalid user identifier")
	}
	userID = strings.ToLower(userID)
	event := deletionTombstone{Version: 1, Kind: "account", UserID: userID, CreatedAt: time.Now().UTC()}
	return s.putDeletionTombstone(ctx, "tombstones/accounts/"+userID+".json", event)
}

func (s *S3Store) RecordObjectDeletion(ctx context.Context, key string) error {
	key, err := cleanKey(key)
	if err != nil {
		return fmt.Errorf("record object deletion: %w", err)
	}
	digest := sha256.Sum256([]byte(key))
	event := deletionTombstone{Version: 1, Kind: "object", StoragePath: key, CreatedAt: time.Now().UTC()}
	return s.putDeletionTombstone(ctx, "tombstones/objects/"+hex.EncodeToString(digest[:])+".json", event)
}

func (s *S3Store) putDeletionTombstone(ctx context.Context, key string, event deletionTombstone) error {
	if s.deletionLedgerBucket == "" {
		return fmt.Errorf("account and object deletion journal is not configured")
	}
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode deletion tombstone: %w", err)
	}
	_, err = s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.deletionLedgerBucket),
		Key:           aws.String(key),
		Body:          strings.NewReader(string(body)),
		ContentLength: aws.Int64(int64(len(body))),
		ContentType:   aws.String("application/json"),
	})
	if err != nil {
		return fmt.Errorf("write deletion tombstone: %w", err)
	}
	return nil
}

func responseErrorStatus(err error) int {
	var responseError *smithyhttp.ResponseError
	if errors.As(err, &responseError) {
		return responseError.HTTPStatusCode()
	}
	return 0
}

var _ ObjectStore = (*S3Store)(nil)
