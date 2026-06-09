package dailyreports

type DailyReport struct {
	ID        string
	ProjectID string
	Summary   string
}

type CreateDailyReportRequest struct {
	ProjectID string
	Summary   string
}

type Repository interface {
	Create(input CreateDailyReportRequest) (*DailyReport, error)
	ListByProject(projectID string) ([]DailyReport, error)
}
