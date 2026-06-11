package httpapi

import "net/http"

func registerAPIRoutes(mux *http.ServeMux) {
	api := "/api/v1"
	mux.HandleFunc(api+"/projects", requireAuth(Projects))
	mux.HandleFunc(api+"/projects/", requireAuth(Projects))
	mux.HandleFunc(api+"/cost-items", requireAuth(CostItems))
	mux.HandleFunc(api+"/cost-items/", requireAuth(CostItems))
	mux.HandleFunc(api+"/daily-reports", requireAuth(withProjectMutationRBAC(DailyReports, "", nil)))
	mux.HandleFunc(api+"/daily-reports/", requireAuth(withProjectMutationRBAC(DailyReports, api+"/daily-reports/", dailyReportProjectID)))
	mux.HandleFunc(api+"/files", requireAuth(withProjectMutationRBAC(Files, "", nil)))
	mux.HandleFunc(api+"/tasks", requireAuth(withProjectMutationRBAC(Tasks, "", nil)))
	mux.HandleFunc(api+"/tasks/", requireAuth(withProjectMutationRBAC(Tasks, api+"/tasks/", taskProjectID)))
	mux.HandleFunc(api+"/audit-logs", requireAuth(AuditLogs))
	mux.HandleFunc(api+"/auth/sms/request", withSMSRequestRateLimit(RequestSMSCode))
	mux.HandleFunc(api+"/auth/sms/verify", VerifySMSCode)
	mux.HandleFunc(api+"/subscriptions/plans", ListPlans)
	mux.HandleFunc(api+"/subscriptions/status", requireAuth(SubscriptionStatus))
}
