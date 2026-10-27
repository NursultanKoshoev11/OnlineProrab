package httpapi

import (
	"context"
	"net/http"
	"time"
)

func productionOBankSandboxMode() bool {
	return appState.IsProduction && appState.OBank.Enabled && appState.OBank.Test
}

func isAllowedProductionOBankTestUser(ctx context.Context, userID string) bool {
	if !productionOBankSandboxMode() {
		return true
	}
	if userID == "" || appState.OBank.TestOnlyPhone == "" || appState.DB == nil || appState.DB.Pool == nil {
		return false
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	var phone string
	if err := appState.DB.Pool.QueryRow(ctx, `SELECT COALESCE(phone, '') FROM users WHERE id = $1`, userID).Scan(&phone); err != nil {
		return false
	}
	return normalizePhone(phone) == appState.OBank.TestOnlyPhone
}

func denyNonTestOBankAccount(w http.ResponseWriter) {
	Error(w, http.StatusForbidden, "sandbox checkout is restricted to the configured test account")
}
