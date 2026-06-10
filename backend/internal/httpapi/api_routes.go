package httpapi

import "net/http"

func registerAPIRoutes(mux *http.ServeMux) {
	api := "/api/v1"
	mux.HandleFunc(api+"/projects", requireAuth(Projects))
	mux.HandleFunc(api+"/projects/", requireAuth(Projects))
	mux.HandleFunc(api+"/cost-items", requireAuth(CostItems))
	mux.HandleFunc(api+"/cost-items/", requireAuth(CostItems))
	mux.HandleFunc(api+"/daily-reports", requireAuth(DailyReports))
	mux.HandleFunc(api+"/daily-reports/", requireAuth(DailyReports))
	mux.HandleFunc(api+"/files", requireAuth(Files))
	mux.HandleFunc(api+"/tasks", requireAuth(Tasks))
	mux.HandleFunc(api+"/tasks/", requireAuth(Tasks))
	mux.HandleFunc(api+"/audit-logs", requireAuth(AuditLogs))
	mux.HandleFunc(api+"/auth/sms/request", RequestSMSCode)
	mux.HandleFunc(api+"/auth/sms/verify", VerifySMSCode)
	mux.HandleFunc(api+"/subscriptions/plans", ListPlans)
	mux.HandleFunc(api+"/subscriptions/status", requireAuth(SubscriptionStatus))
}
