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

func hasProjectPermission(ctx context.Context, userID, projectID string, required ProjectPermission) bool {
	var role string
	var status string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT pm.role, p.status
		FROM project_members pm
		JOIN projects p ON p.id = pm.project_id
		WHERE pm.user_id = $1
		  AND pm.project_id = $2
		  AND p.deleted_at IS NULL
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
