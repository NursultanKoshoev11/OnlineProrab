package projects

type Project struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	BudgetAmount float64 `json:"budget_amount"`
	Currency     string  `json:"currency"`
	Status       string  `json:"status"`
}

type CreateProjectRequest struct {
	Name         string  `json:"name"`
	BudgetAmount float64 `json:"budget_amount"`
	Currency     string  `json:"currency"`
}

type Repository interface {
	Create(ownerID string, req CreateProjectRequest) (Project, error)
	List(ownerID string) ([]Project, error)
}
