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

func canAccessProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionRead)
}

func canContributeToProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionContribute)
}

func canManageProject(ctx context.Context, userID, projectID string) bool {
	return hasProjectPermission(ctx, userID, projectID, PermissionManage)
}

func hasProjectPermission(ctx context.Context, userID, projectID string, required ProjectPermission) bool {
	var role string
	err := appState.DB.Pool.QueryRow(ctx, `
		SELECT role
		FROM project_members
		WHERE user_id = $1 AND project_id = $2
	`, userID, projectID).Scan(&role)
	if err != nil {
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
