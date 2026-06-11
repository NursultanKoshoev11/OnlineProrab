package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
)

type entityProjectResolver func(context.Context, string) (string, bool)

func withProjectMutationRBAC(next http.HandlerFunc, itemPathPrefix string, resolver entityProjectResolver) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions {
			next(w, r)
			return
		}

		userID := userIDFromContext(r.Context())
		projectID, ok := mutationProjectID(r, itemPathPrefix, resolver)
		if !ok || projectID == "" {
			Error(w, http.StatusBadRequest, "project_id is required")
			return
		}

		if r.Method == http.MethodDelete {
			if !canManageProject(r.Context(), userID, projectID) {
				Error(w, http.StatusForbidden, "project management permission required")
				return
			}
		} else if !canContributeToProject(r.Context(), userID, projectID) {
			Error(w, http.StatusForbidden, "project contribution permission required")
			return
		}

		next(w, r)
	}
}

func mutationProjectID(r *http.Request, itemPathPrefix string, resolver entityProjectResolver) (string, bool) {
	if r.Method == http.MethodPost {
		body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		if err != nil {
			return "", false
		}
		r.Body = io.NopCloser(bytes.NewReader(body))
		var payload struct {
			ProjectID string `json:"project_id"`
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			return "", false
		}
		return payload.ProjectID, payload.ProjectID != ""
	}

	if resolver == nil || itemPathPrefix == "" {
		return "", false
	}
	entityID := resourceIDFromPath(r.URL.Path, itemPathPrefix)
	if entityID == "" {
		return "", false
	}
	return resolver(r.Context(), entityID)
}
