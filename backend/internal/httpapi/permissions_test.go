package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRoleAllowsReadForAllProjectRoles(t *testing.T) {
	roles := []string{ProjectRoleOwner, ProjectRoleManager, ProjectRoleWorker, ProjectRoleViewer}
	for _, role := range roles {
		if !roleAllows(role, PermissionRead) {
			t.Fatalf("expected role %q to have read permission", role)
		}
	}
}

func TestRoleAllowsContributionForOwnerManagerWorker(t *testing.T) {
	allowed := []string{ProjectRoleOwner, ProjectRoleManager, ProjectRoleWorker}
	for _, role := range allowed {
		if !roleAllows(role, PermissionContribute) {
			t.Fatalf("expected role %q to have contribution permission", role)
		}
	}
	if roleAllows(ProjectRoleViewer, PermissionContribute) {
		t.Fatal("viewer must not have contribution permission")
	}
}

func TestRoleAllowsManagementOnlyForOwnerAndManager(t *testing.T) {
	if !roleAllows(ProjectRoleOwner, PermissionManage) {
		t.Fatal("owner must have management permission")
	}
	if !roleAllows(ProjectRoleManager, PermissionManage) {
		t.Fatal("manager must have management permission")
	}
	if roleAllows(ProjectRoleWorker, PermissionManage) {
		t.Fatal("worker must not have management permission")
	}
	if roleAllows(ProjectRoleViewer, PermissionManage) {
		t.Fatal("viewer must not have management permission")
	}
}

func TestUnknownRoleHasNoPermissions(t *testing.T) {
	if roleAllows("unknown", PermissionRead) || roleAllows("unknown", PermissionContribute) || roleAllows("unknown", PermissionManage) {
		t.Fatal("unknown role must not have permissions")
	}
}

func TestProjectMutationRBACRejectsUnsupportedMethods(t *testing.T) {
	called := false
	handler := withProjectMutationRBAC(
		func(http.ResponseWriter, *http.Request) { called = true },
		"/api/v1/items/",
		nil,
	)
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPut, "/api/v1/items/item-1", nil)

	handler(recorder, request)

	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", recorder.Code)
	}
	if called {
		t.Fatal("unsupported method must not reach the wrapped handler")
	}
}
