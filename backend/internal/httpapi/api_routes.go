package httpapi

import "net/http"

func registerAPIRoutes(mux *http.ServeMux) {
	api := "/api/v1"
	mux.HandleFunc(api+"/projects", requireAuth(Projects))
	mux.HandleFunc(api+"/projects/", requireAuth(Projects))
	mux.HandleFunc(api+"/project-members", requireAuth(ProjectMembers))
	mux.HandleFunc(api+"/project-members/", requireAuth(ProjectMember))
	mux.HandleFunc(api+"/project-invites", requireAuth(CreateProjectInvite))
	mux.HandleFunc(api+"/project-invites/accept", requireAuth(AcceptProjectInvite))
	mux.HandleFunc(api+"/cost-items", requireAuth(withProjectMutationRBAC(CostItems, "", nil)))
	mux.HandleFunc(api+"/cost-items/", requireAuth(withProjectMutationRBAC(CostItems, api+"/cost-items/", costItemProjectID)))
	mux.HandleFunc(api+"/daily-reports", requireAuth(withProjectMutationRBAC(DailyReports, "", nil)))
	mux.HandleFunc(api+"/daily-reports/", requireAuth(withProjectMutationRBAC(DailyReports, api+"/daily-reports/", dailyReportProjectID)))
	mux.HandleFunc(api+"/files", requireAuth(withProjectMutationRBAC(Files, "", nil)))
	mux.HandleFunc(api+"/files/", requireAuth(withProjectMutationRBAC(Files, api+"/files/", fileProjectID)))
	mux.HandleFunc(api+"/tasks", requireAuth(withProjectMutationRBAC(Tasks, "", nil)))
	mux.HandleFunc(api+"/tasks/", requireAuth(withProjectMutationRBAC(Tasks, api+"/tasks/", taskProjectID)))
	mux.HandleFunc(api+"/audit-logs", requireAuth(AuditLogs))
	mux.HandleFunc(api+"/auth/sms/request", withSMSRequestRateLimit(RequestSMSCode))
	mux.HandleFunc(api+"/auth/sms/verify", withSMSVerifyRateLimit(VerifySMSCode))
	mux.HandleFunc(api+"/auth/session", requireAuth(CreateSession))
	mux.HandleFunc(api+"/auth/session/refresh", RefreshSession)
	mux.HandleFunc(api+"/auth/session/logout", LogoutSession)
	mux.HandleFunc(api+"/subscriptions/plans", ListPlans)
	mux.HandleFunc(api+"/subscriptions/status", requireAuth(SubscriptionStatus))
}
