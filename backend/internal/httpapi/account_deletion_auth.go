package httpapi

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
)

const (
	accountDeletionTokenScope = "account:delete"
	accountDeletionTokenTTL   = 10 * time.Minute
)

// VerifyAccountDeletionSMSCode verifies a phone challenge without creating a
// user, updating account state, or accepting project invitations.
func VerifyAccountDeletionSMSCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	var req verifySMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.Phone = normalizePhone(req.Phone)
	req.Code = strings.TrimSpace(req.Code)
	if !phoneRe.MatchString(req.Phone) || len(req.Code) != 6 {
		Error(w, http.StatusBadRequest, "invalid phone or code")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
		return
	}
	defer tx.Rollback(ctx)

	var codeID string
	var codeHash string
	var attempts int
	err = tx.QueryRow(ctx, `
		SELECT id::text, code_hash, attempts
		FROM sms_login_codes
		WHERE phone = $1 AND consumed_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC
		LIMIT 1
		FOR UPDATE
	`, req.Phone).Scan(&codeID, &codeHash, &attempts)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			Error(w, http.StatusUnauthorized, "invalid or expired code")
		} else {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
		}
		return
	}
	if attempts >= 5 {
		Error(w, http.StatusTooManyRequests, "too many attempts")
		return
	}
	if subtle.ConstantTimeCompare([]byte(hashLoginCode(req.Phone, req.Code)), []byte(codeHash)) != 1 {
		if _, err := tx.Exec(ctx, `UPDATE sms_login_codes SET attempts = attempts + 1 WHERE id = $1`, codeID); err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		if err := tx.Commit(ctx); err != nil {
			Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
			return
		}
		Error(w, http.StatusUnauthorized, "invalid or expired code")
		return
	}

	var userID string
	err = tx.QueryRow(ctx, `SELECT id::text FROM users WHERE phone = $1`, req.Phone).Scan(&userID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
		return
	}
	accountNotFound := errors.Is(err, pgx.ErrNoRows)
	if _, err := tx.Exec(ctx, `UPDATE sms_login_codes SET consumed_at = now() WHERE id = $1`, codeID); err != nil {
		Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusServiceUnavailable, "login service is temporarily unavailable")
		return
	}
	if accountNotFound {
		Error(w, http.StatusNotFound, "account not found")
		return
	}

	token, err := signAccountDeletionToken(userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to sign deletion token")
		return
	}
	JSON(w, http.StatusOK, authResponse{
		Status:      "verified",
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int64(accountDeletionTokenTTL.Seconds()),
		UserID:      userID,
	})
}

func signAccountDeletionToken(userID string) (string, error) {
	claims := jwt.MapClaims{
		"sub":   userID,
		"scope": accountDeletionTokenScope,
		"exp":   time.Now().Add(accountDeletionTokenTTL).Unix(),
		"iat":   time.Now().Unix(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(appState.JWTSecret))
}

func parseAccountDeletionToken(rawToken string) (string, error) {
	token, err := jwt.Parse(
		rawToken,
		func(token *jwt.Token) (any, error) {
			if token.Method.Alg() != jwt.SigningMethodHS256.Alg() {
				return nil, fmt.Errorf("unexpected signing method")
			}
			return []byte(appState.JWTSecret), nil
		},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
	)
	if err != nil || !token.Valid {
		return "", fmt.Errorf("invalid token")
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || claims["scope"] != accountDeletionTokenScope {
		return "", fmt.Errorf("invalid deletion token scope")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", fmt.Errorf("missing subject")
	}
	return sub, nil
}

// requireAccountDeletionAuth accepts normal app access tokens and the narrow,
// short-lived token issued by the public account-deletion verification flow.
func requireAccountDeletionAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			Error(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		rawToken := strings.TrimPrefix(header, "Bearer ")
		userID, err := parseAccountDeletionToken(rawToken)
		if err != nil {
			userID, err = parseAccessToken(rawToken)
		}
		if err != nil {
			Error(w, http.StatusUnauthorized, "invalid token")
			return
		}
		if !requireActiveAccount(w, r, userID) {
			return
		}
		next(w, r.WithContext(withUserID(r.Context(), userID)))
	}
}
