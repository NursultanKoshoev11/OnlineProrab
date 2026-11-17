package httpapi

import (
	"net/http"
	"time"
)

// newOutboundHTTPClient refuses redirects so provider requests never resend
// private request bodies to a URL supplied by a redirect response.
func newOutboundHTTPClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout: timeout,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}
