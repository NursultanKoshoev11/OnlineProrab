package httpapi

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type subscriptionPlan struct {
	ID                    string
	Name                  string
	PriceKGS              int
	AnnualDiscountPercent int
	MaxProjects           int
	MaxInvitedMembers     int
	TrialDays             int
}

var subscriptionPlans = []subscriptionPlan{
	{
		ID:                    "trial",
		Name:                  "Пробный период",
		PriceKGS:              0,
		AnnualDiscountPercent: 0,
		MaxProjects:           1,
		MaxInvitedMembers:     0,
		TrialDays:             30,
	},
	{
		ID:                    "standard",
		Name:                  "Стандартный",
		PriceKGS:              3000,
		AnnualDiscountPercent: 10,
		MaxProjects:           5,
		MaxInvitedMembers:     5,
	},
	{
		ID:                    "max",
		Name:                  "Максимальный",
		PriceKGS:              5000,
		AnnualDiscountPercent: 15,
		MaxProjects:           20,
		MaxInvitedMembers:     20,
	},
}

var (
	errSubscriptionExpired = errors.New("subscription expired")
	errProjectPlanLimit    = errors.New("project plan limit reached")
	errMemberPlanLimit     = errors.New("member plan limit reached")
)

type subscriptionState struct {
	Plan             subscriptionPlan
	Status           string
	BillingPeriod    string
	StartedAt        time.Time
	TrialEndsAt      time.Time
	CurrentPeriodEnd *time.Time
}

type subscriptionQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

func planByCode(code string) (subscriptionPlan, error) {
	for _, plan := range subscriptionPlans {
		if plan.ID == code {
			return plan, nil
		}
	}
	return subscriptionPlan{}, fmt.Errorf("unknown subscription plan %q", code)
}

func planPrice(plan subscriptionPlan, billingPeriod string) (int, error) {
	switch billingPeriod {
	case "month":
		return plan.PriceKGS, nil
	case "year":
		return plan.PriceKGS * 12 * (100 - plan.AnnualDiscountPercent) / 100, nil
	default:
		return 0, fmt.Errorf("unknown billing period %q", billingPeriod)
	}
}

func ensureSubscription(ctx context.Context, db subscriptionQuerier, userID string, lock bool) (subscriptionState, error) {
	if _, err := db.Exec(ctx, `
        INSERT INTO account_subscriptions (user_id, plan_code, status, started_at, trial_ends_at)
        SELECT id, 'trial', 'trialing', created_at, created_at + interval '30 days'
        FROM users
        WHERE id = $1
        ON CONFLICT (user_id) DO NOTHING
    `, userID); err != nil {
		return subscriptionState{}, fmt.Errorf("create account subscription: %w", err)
	}

	query := `
        SELECT plan_code, status, billing_period, started_at, trial_ends_at, current_period_end
        FROM account_subscriptions
        WHERE user_id = $1`
	if lock {
		query += " FOR UPDATE"
	}

	var state subscriptionState
	var planCode string
	var currentPeriodEnd *time.Time
	if err := db.QueryRow(ctx, query, userID).Scan(
		&planCode,
		&state.Status,
		&state.BillingPeriod,
		&state.StartedAt,
		&state.TrialEndsAt,
		&currentPeriodEnd,
	); err != nil {
		return subscriptionState{}, fmt.Errorf("load account subscription: %w", err)
	}

	plan, err := planByCode(planCode)
	if err != nil {
		return subscriptionState{}, err
	}
	state.Plan = plan
	state.CurrentPeriodEnd = currentPeriodEnd
	if state.BillingPeriod == "" {
		state.BillingPeriod = "month"
	}

	now := time.Now().UTC()
	expired := state.Status == "trialing" && !state.TrialEndsAt.After(now)
	if state.Status == "active" && state.CurrentPeriodEnd != nil && !state.CurrentPeriodEnd.After(now) {
		expired = true
	}
	if expired {
		if _, err := db.Exec(ctx, `
            UPDATE account_subscriptions
            SET status = 'expired', updated_at = now()
            WHERE user_id = $1
        `, userID); err != nil {
			return subscriptionState{}, fmt.Errorf("expire account subscription: %w", err)
		}
		state.Status = "expired"
	}
	return state, nil
}

func subscriptionHTTPError(err error) (int, string, bool) {
	switch {
	case errors.Is(err, errSubscriptionExpired):
		return http.StatusForbidden, "subscription is expired; choose a paid plan", true
	case errors.Is(err, errProjectPlanLimit):
		return http.StatusForbidden, "project limit reached for the current plan", true
	case errors.Is(err, errMemberPlanLimit):
		return http.StatusForbidden, "participant limit reached for the current plan", true
	default:
		return 0, "", false
	}
}

func ensureProjectCreationAllowed(ctx context.Context, tx pgx.Tx, userID string) error {
	state, err := ensureSubscription(ctx, tx, userID, true)
	if err != nil {
		return err
	}
	if state.Status != "trialing" && state.Status != "active" {
		return errSubscriptionExpired
	}

	var projectCount int
	if err := tx.QueryRow(ctx, `
        SELECT COUNT(*)
        FROM projects
        WHERE owner_id = $1
          AND deleted_at IS NULL
          AND status = 'active'
    `, userID).Scan(&projectCount); err != nil {
		return fmt.Errorf("count account projects: %w", err)
	}
	if projectCount >= state.Plan.MaxProjects {
		return errProjectPlanLimit
	}
	return nil
}

func ensureProjectMemberCapacity(ctx context.Context, tx pgx.Tx, projectID, phone string) error {
	var ownerID string
	if err := tx.QueryRow(ctx, `
        SELECT owner_id::text
        FROM projects
        WHERE id = $1 AND deleted_at IS NULL
        FOR UPDATE
    `, projectID).Scan(&ownerID); err != nil {
		return fmt.Errorf("load project owner: %w", err)
	}

	state, err := ensureSubscription(ctx, tx, ownerID, true)
	if err != nil {
		return err
	}
	if state.Status != "trialing" && state.Status != "active" {
		return errSubscriptionExpired
	}

	var participantCount int
	if err := tx.QueryRow(ctx, `
        SELECT
            (SELECT COUNT(*) FROM project_members
             WHERE project_id = $1 AND role <> 'owner')
          + (SELECT COUNT(*) FROM project_invites
             WHERE project_id = $1
               AND accepted_at IS NULL
               AND revoked_at IS NULL
               AND expires_at > now()
               AND phone <> $2)
    `, projectID, phone).Scan(&participantCount); err != nil {
		return fmt.Errorf("count project participants: %w", err)
	}
	if participantCount >= state.Plan.MaxInvitedMembers {
		return errMemberPlanLimit
	}
	return nil
}
