package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
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

// developmentSMSCode is intentionally available only when the backend runs
// outside production without a configured SMS sender. It keeps local/staging
// smoke tests usable without weakening production authentication.
const developmentSMSCode = "111111"

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

	code, err := issueSMSCode()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to generate code")
		return
	}
	codeHash := hashLoginCode(req.Phone, code)
	expiresAt := time.Now().UTC().Add(5 * time.Minute)

	dbCtx, dbCancel := context.WithTimeout(r.Context(), 3*time.Second)
	var codeID string
	err = appState.DB.Pool.QueryRow(dbCtx, `
		INSERT INTO sms_login_codes (phone, code_hash, expires_at)
		VALUES ($1, $2, $3)
		RETURNING id::text
	`, req.Phone, codeHash, expiresAt).Scan(&codeID)
	dbCancel()
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create login code")
		return
	}

	if appState.SMSSender != nil {
		sendCtx, sendCancel := context.WithTimeout(r.Context(), 12*time.Second)
		err = appState.SMSSender.SendLoginCode(sendCtx, req.Phone, code)
		sendCancel()
		if err != nil {
			cleanupSMSCode(codeID)
			Error(w, http.StatusBadGateway, "failed to deliver login code")
			return
		}
	} else if appState.IsProduction {
		cleanupSMSCode(codeID)
		Error(w, http.StatusServiceUnavailable, "SMS service is unavailable")
		return
	}

	invalidateOlderSMSCodes(req.Phone, codeID)

	response := map[string]any{"status": "code_requested", "expires_in": 300}
	if !appState.IsProduction && appState.SMSSender == nil {
		response["dev_code"] = code
	}
	JSON(w, http.StatusAccepted, response)
}

func issueSMSCode() (string, error) {
	if !appState.IsProduction && appState.SMSSender == nil {
		return developmentSMSCode, nil
	}
	return generateSMSCode()
}

func cleanupSMSCode(codeID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, _ = appState.DB.Pool.Exec(ctx, `DELETE FROM sms_login_codes WHERE id = $1`, codeID)
}

func invalidateOlderSMSCodes(phone, keepCodeID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, _ = appState.DB.Pool.Exec(ctx, `
		UPDATE sms_login_codes
		SET consumed_at = now()
		WHERE phone = $1
		  AND id <> $2
		  AND consumed_at IS NULL
	`, phone, keepCodeID)
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

	tx, err := appState.DB.Pool.Begin(ctx)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to start login transaction")
		return
	}
	defer tx.Rollback(ctx)

	var userID string
	err = tx.QueryRow(ctx, `
		INSERT INTO users (phone)
		VALUES ($1)
		ON CONFLICT (phone) DO UPDATE SET updated_at = now()
		RETURNING id::text
	`, req.Phone).Scan(&userID)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to create user")
		return
	}

	// A phone invitation is intentionally completed during SMS verification.
	// This keeps the normal flow to: manager enters a phone, partner logs in,
	// and the object appears without exposing an invitation token in production.
	rows, err := tx.Query(ctx, `
		SELECT id::text, project_id::text, role
		FROM project_invites
		WHERE phone = $1
		  AND accepted_at IS NULL
		  AND revoked_at IS NULL
		  AND expires_at > now()
		ORDER BY created_at
		FOR UPDATE
	`, req.Phone)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load project invitations")
		return
	}
	type pendingProjectInvite struct {
		id        string
		projectID string
		role      string
	}
	pendingInvites := make([]pendingProjectInvite, 0)
	for rows.Next() {
		var invite pendingProjectInvite
		if err := rows.Scan(&invite.id, &invite.projectID, &invite.role); err != nil {
			rows.Close()
			Error(w, http.StatusInternalServerError, "failed to read project invitation")
			return
		}
		pendingInvites = append(pendingInvites, invite)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		Error(w, http.StatusInternalServerError, "failed to read project invitations")
		return
	}
	rows.Close()

	for _, invite := range pendingInvites {
		if _, err := tx.Exec(ctx, `
			INSERT INTO project_members (project_id, user_id, role)
			VALUES ($1, $2, $3)
			ON CONFLICT (project_id, user_id) DO NOTHING
		`, invite.projectID, userID, invite.role); err != nil {
			Error(w, http.StatusInternalServerError, "failed to apply project invitation")
			return
		}
		if _, err := tx.Exec(ctx, `
			UPDATE project_invites SET accepted_at = now() WHERE id = $1
		`, invite.id); err != nil {
			Error(w, http.StatusInternalServerError, "failed to complete project invitation")
			return
		}
		if _, auditErr := tx.Exec(ctx, `
			INSERT INTO audit_logs (actor_id, project_id, action, entity_type, entity_id, metadata)
			VALUES ($1, $2, 'accept_invite', 'project_member', $1, jsonb_build_object('role', $3::text, 'source', 'sms_login'))
		`, userID, invite.projectID, invite.role); auditErr != nil {
			log.Printf("verify sms: failed to write invite audit log: %v", auditErr)
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE sms_login_codes SET consumed_at = now() WHERE id = $1`, codeID); err != nil {
		log.Printf("verify sms: failed to complete login code: %v", err)
		Error(w, http.StatusInternalServerError, "failed to complete login code")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		Error(w, http.StatusInternalServerError, "failed to complete login")
		return
	}

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
