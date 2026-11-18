package httpapi

import "context"

const (
	ProjectRoleOwner   = "owner"
	ProjectRoleManager = "manager"
	ProjectRoleWorker  = "worker"
	ProjectRoleViewer  = "viewer"
)

type ProjectPermission int

const (
	PermissionRead ProjectPermission = iota
	PermissionContribute
	PermissionManage
)

func canContributeToProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionContribute)
}

func canManageProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionManage)
}

// canManageProjectLifecycle is used only for project-level state transitions
// such as restoring an archived project. Archived projects reject ordinary
// mutations, but their managers must still be able to bring them back.
func canManageProjectLifecycle(ctx context.Context, userID, projectID string) bool {
	var role string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT pm.role
		FROM project_members pm
		JOIN projects p ON p.id = pm.project_id
		WHERE pm.user_id = $1
		  AND pm.project_id = $2
		  AND p.deleted_at IS NULL
	`, userID, projectID).Scan(&role)
	return err == nil && roleAllows(role, PermissionManage)
}

func hasProjectPermission(ctx context.Context, userID, projectID string, required ProjectPermission) bool {
	var role string
	var status string
	// Access to a project is paid for by its owner: members keep working while
	// the owner's subscription is current, whatever their own plan is.
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT pm.role, p.status
		FROM project_members pm
		JOIN projects p ON p.id = pm.project_id
		WHERE pm.user_id = $1
		  AND pm.project_id = $2
		  AND p.deleted_at IS NULL
		  AND `+ownerSubscriptionCurrentSQL+`
	`, userID, projectID).Scan(&role, &status)
	if err != nil {
		return false
	}
	if required != PermissionRead && status != "active" {
		return false
	}
	return roleAllows(role, required)
}

func roleAllows(role string, required ProjectPermission) bool {
	switch required {
	case PermissionRead:
		return role == ProjectRoleOwner || role == ProjectRoleManager || role == ProjectRoleWorker || role == ProjectRoleViewer
	case PermissionContribute:
		return role == ProjectRoleOwner || role == ProjectRoleManager || role == ProjectRoleWorker
	case PermissionManage:
		return role == ProjectRoleOwner || role == ProjectRoleManager
	default:
		return false
	}
}

// projectMemberRole returns the caller's role in an active, non-deleted
// project, or "" when the caller is not a member.
func projectMemberRole(ctx context.Context, userID, projectID string) string {
	var role string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT pm.role
		FROM project_members pm
		JOIN projects p ON p.id = pm.project_id
		WHERE pm.user_id = $1
		  AND pm.project_id = $2
		  AND p.deleted_at IS NULL
	`, userID, projectID).Scan(&role)
	if err != nil {
		return ""
	}
	return role
}

// canChangeTeamMember decides whether an actor may invite, re-role or remove a
// member. Owners manage everyone except the owner. Managers manage only
// workers and viewers and cannot grant the manager role, so one manager
// cannot demote or remove another. currentRole is "" for a new invitation;
// newRole is "" for a removal.
func canChangeTeamMember(actorRole, currentRole, newRole string) bool {
	if currentRole == ProjectRoleOwner || newRole == ProjectRoleOwner {
		return false
	}
	switch actorRole {
	case ProjectRoleOwner:
		return true
	case ProjectRoleManager:
		limited := func(role string) bool {
			return role == "" || role == ProjectRoleWorker || role == ProjectRoleViewer
		}
		return limited(currentRole) && limited(newRole)
	default:
		return false
	}
}

// ownerSubscriptionCurrentSQL is true when the owner of project "p" has a
// current trial or paid period. Owners without a subscription row predate
// subscriptions and keep access until their row is created on next login.
const ownerSubscriptionCurrentSQL = `NOT EXISTS (
		SELECT 1 FROM account_subscriptions s
		WHERE s.user_id = p.owner_id
		  AND NOT (
			(s.status = 'trialing' AND s.trial_ends_at > now())
			OR (s.status = 'active' AND (s.current_period_end IS NULL OR s.current_period_end > now()))
		  )
	)`
