package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type requestSMSCodeRequest struct {
	Phone string `json:"phone"`
	Name  string `json:"name"`
}

type verifySMSCodeRequest struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

type authResponse struct {
	Status      string `json:"status"`
	AccessToken string `json:"access_token,omitempty"`
	TokenType   string `json:"token_type,omitempty"`
	ExpiresIn   int64  `json:"expires_in,omitempty"`
	UserID      string `json:"user_id,omitempty"`
}

var phoneRe = regexp.MustCompile(`^\+?[0-9]{9,15}$`)

func RequestSMSCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	var req requestSMSCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		Error(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	req.Phone = normalizePhone(req.Phone)
	if !phoneRe.MatchString(req.Phone) {
		Error(w, http.StatusBadRequest, "invalid phone number")
		return
	}

	code, err := generateSMSCode()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to generate code")
		return
	}
	codeHash := hashLoginCode(req.Phone, code)
	expiresAt := time.Now().UTC().Add(5 * time.Minute)

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	_, err = appState.DB.Pool.Exec(ctx, `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, $3)
	`, req.Phone, codeHash, expiresAt)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create login code")
		return
	}

	// The code is returned only in non-production/dev foundation mode until an SMS provider is connected.
	response := map[string]any{"status": "code_requested", "expires_in": 300}
	if appState.JWTSecret == "dev-only-change-me" {
		response["dev_code"] = code
	}
	JSON(w, http.StatusAccepted, response)
}

func VerifySMSCode(w http.ResponseWriter, r *http.Request) {
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

	var codeID string
	var codeHash string
	var attempts int
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT id::text, code_hash, attempts
		FROM sms_login_codes
		WHERE phone = $1 AND consumed_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC
		LIMIT 1
	`, req.Phone).Scan(&codeID, &codeHash, &attempts)
	if err != nil {
		Error(w, http.StatusUnauthorized, "invalid or expired code")
		return
	}
	if attempts >= 5 {
		Error(w, http.StatusTooManyRequests, "too many attempts")
		return
	}

	if hashLoginCode(req.Phone, req.Code) != codeHash {
		_, _ = appState.DB.Pool.Exec(ctx, `UPDATE sms_login_codes SET attempts = attempts + 1 WHERE id = $1`, codeID)
		Error(w, http.StatusUnauthorized, "invalid or expired code")
		return
	}

	var userID string
	err = appState.DB.Pool.QueryRow(ctx, `
		INSERT INTO users (phone)
		VALUES ($1)
		ON CONFLICT (phone) DO UPDATE SET updated_at = now()
		RETURNING id::text
	`, req.Phone).Scan(&userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create user")
		return
	}

	_, _ = appState.DB.Pool.Exec(ctx, `UPDATE sms_login_codes SET consumed_at = now() WHERE id = $1`, codeID)

	token, err := signAccessToken(userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to sign token")
		return
	}

	JSON(w, http.StatusOK, authResponse{
		Status:      "verified",
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int64(appState.AccessTokenTTL.Seconds()),
		UserID:      userID,
	})
}

func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			Error(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		userID, err := parseAccessToken(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			Error(w, http.StatusUnauthorized, "invalid token")
			return
		}
		next(w, r.WithContext(withUserID(r.Context(), userID)))
	}
}

func signAccessToken(userID string) (string, error) {
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(appState.AccessTokenTTL).Unix(),
		"iat": time.Now().Unix(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(appState.JWTSecret))
}

func parseAccessToken(rawToken string) (string, error) {
	token, err := jwt.Parse(rawToken, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return []byte(appState.JWTSecret), nil
	})
	if err != nil || !token.Valid {
		return "", fmt.Errorf("invalid token")
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", fmt.Errorf("invalid claims")
	}
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", fmt.Errorf("missing subject")
	}
	return sub, nil
}

func generateSMSCode() (string, error) {
	buf := make([]byte, 4)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	value := int(buf[0])<<24 | int(buf[1])<<16 | int(buf[2])<<8 | int(buf[3])
	if value < 0 {
		value = -value
	}
	return fmt.Sprintf("%06d", value%1000000), nil
}

func hashLoginCode(phone, code string) string {
	sum := sha256.Sum256([]byte(phone + ":" + code + ":" + appState.JWTSecret))
	return hex.EncodeToString(sum[:])
}

func normalizePhone(phone string) string {
	return strings.ReplaceAll(strings.TrimSpace(phone), " ", "")
}
