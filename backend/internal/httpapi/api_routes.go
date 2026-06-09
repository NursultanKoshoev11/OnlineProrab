package httpapi

import "net/http"

func registerAPIRoutes(mux *http.ServeMux) {
	api := "/api/v1"
	mux.HandleFunc(api+"/projects", Projects)
	mux.HandleFunc(api+"/cost-items", CostItems)
	mux.HandleFunc(api+"/daily-reports", DailyReports)
	mux.HandleFunc(api+"/files", Files)
	mux.HandleFunc(api+"/auth/sms/request", RequestSMSCode)
	mux.HandleFunc(api+"/auth/sms/verify", VerifySMSCode)
	mux.HandleFunc(api+"/subscriptions/plans", ListPlans)
	mux.HandleFunc(api+"/subscriptions/status", SubscriptionStatus)
}
