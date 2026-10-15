package storage

import (
	"testing"
	"time"
)

func TestDeletionRetryDelayCapsAndIncreases(t *testing.T) {
	cases := []struct {
		attempts int
		want     time.Duration
	}{
		{attempts: -1, want: 5 * time.Second},
		{attempts: 0, want: 5 * time.Second},
		{attempts: 1, want: 10 * time.Second},
		{attempts: 2, want: 20 * time.Second},
		{attempts: 9, want: 2560 * time.Second},
		{attempts: 10, want: time.Hour},
		{attempts: 100, want: time.Hour},
	}
	for _, testCase := range cases {
		if got := deletionRetryDelay(testCase.attempts); got != testCase.want {
			t.Errorf("deletionRetryDelay(%d)=%s, want %s", testCase.attempts, got, testCase.want)
		}
	}
}
