package httpapi

import (
	"context"
	"net/http"
	"time"
)

func ListPlans(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	plans := make([]map[string]any, 0, len(subscriptionPlans))
	for _, plan := range subscriptionPlans {
		annualPrice, _ := planPrice(plan, "year")
		plans = append(plans, map[string]any{
			"id":                      plan.ID,
			"name":                    plan.Name,
			"price_kgs":               plan.PriceKGS,
			"billing_period":          "month",
			"annual_price_kgs":        annualPrice,
			"annual_discount_percent": plan.AnnualDiscountPercent,
			"billing_options": []map[string]any{
				{"period": "month", "price_kgs": plan.PriceKGS, "discount_percent": 0},
				{"period": "year", "price_kgs": annualPrice, "discount_percent": plan.AnnualDiscountPercent},
			},
			"trial_days":          plan.TrialDays,
			"max_projects":        plan.MaxProjects,
			"max_invited_members": plan.MaxInvitedMembers,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"plans": plans})
}

func SubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		Error(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	if appState.DB == nil || appState.DB.Pool == nil {
		Error(w, http.StatusServiceUnavailable, "database is not available")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	userID := userIDFromContext(r.Context())
	state, err := ensureSubscription(ctx, appState.DB.Pool, userID, false)
	if err != nil {
		Error(w, http.StatusInternalServerError, "failed to load subscription")
		return
	}

	endsAt := state.TrialEndsAt
	if state.CurrentPeriodEnd != nil {
		endsAt = *state.CurrentPeriodEnd
	}
	priceKGS, _ := planPrice(state.Plan, state.BillingPeriod)
	discountPercent := 0
	if state.BillingPeriod == "year" {
		discountPercent = state.Plan.AnnualDiscountPercent
	}

	response := map[string]any{
		"user_id":             userID,
		"plan":                state.Plan.ID,
		"status":              state.Status,
		"billing_period":      state.BillingPeriod,
		"price_kgs":           priceKGS,
		"discount_percent":    discountPercent,
		"started_at":          state.StartedAt.UTC().Format(time.RFC3339),
		"trial_ends_at":       state.TrialEndsAt.UTC().Format(time.RFC3339),
		"ends_at":             endsAt.UTC().Format(time.RFC3339),
		"max_projects":        state.Plan.MaxProjects,
		"max_invited_members": state.Plan.MaxInvitedMembers,
	}
	if state.CurrentPeriodEnd != nil {
		response["current_period_end"] = state.CurrentPeriodEnd.UTC().Format(time.RFC3339)
	}
	writeJSON(w, http.StatusOK, response)
}
