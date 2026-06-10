package httpapi

import "net/http"

func NewRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", Health)
	mux.HandleFunc("/ready", Ready)
	registerAPIRoutes(mux)
	return withMiddleware(mux)
}
