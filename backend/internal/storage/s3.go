package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

type S3Options struct {
	Region          string
	Bucket          string
	Endpoint        string
	AccessKeyID     string
	SecretAccessKey string
	SessionToken    string
	ForcePathStyle  bool
}

type S3Store struct {
	client *s3.Client
	bucket string
}

func NewS3(ctx context.Context, options S3Options) (*S3Store, error) {
	options.Region = strings.TrimSpace(options.Region)
	options.Bucket = strings.TrimSpace(options.Bucket)
	options.Endpoint = strings.TrimSpace(options.Endpoint)
	options.AccessKeyID = strings.TrimSpace(options.AccessKeyID)
	options.SecretAccessKey = strings.TrimSpace(options.SecretAccessKey)
	options.SessionToken = strings.TrimSpace(options.SessionToken)
	if options.Region == "" || options.Bucket == "" {
		return nil, fmt.Errorf("S3 region and bucket are required")
	}
	if (options.AccessKeyID == "") != (options.SecretAccessKey == "") {
		return nil, fmt.Errorf("S3 access key ID and secret access key must be configured together")
	}

	loadOptions := []func(*awsconfig.LoadOptions) error{
		awsconfig.WithRegion(options.Region),
	}
	if options.AccessKeyID != "" {
		loadOptions = append(loadOptions, awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
			options.AccessKeyID,
			options.SecretAccessKey,
			options.SessionToken,
		)))
	}
	awsConfig, err := awsconfig.LoadDefaultConfig(ctx, loadOptions...)
	if err != nil {
		return nil, fmt.Errorf("load S3 client configuration: %w", err)
	}
	credentialCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if _, err := awsConfig.Credentials.Retrieve(credentialCtx); err != nil {
		return nil, fmt.Errorf("S3 credentials are unavailable")
	}

	client := s3.NewFromConfig(awsConfig, func(clientOptions *s3.Options) {
		clientOptions.UsePathStyle = options.ForcePathStyle
		if options.Endpoint != "" {
			clientOptions.BaseEndpoint = aws.String(options.Endpoint)
		}
	})
	return &S3Store{client: client, bucket: options.Bucket}, nil
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
