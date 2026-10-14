package sms

import "net/http"

func clientWithoutRedirects(client *http.Client) *http.Client {
	// SMS requests contain provider credentials or one-time codes; never replay them to a redirect target.
	clientCopy := *client
	clientCopy.CheckRedirect = func(_ *http.Request, _ []*http.Request) error {
		return http.ErrUseLastResponse
	}
	return &clientCopy
}
