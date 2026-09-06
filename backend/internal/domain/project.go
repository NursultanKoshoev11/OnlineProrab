package domain

type Project struct {
	ID           string
	OwnerID      string
	Name         string
	Type         string
	Address      string
	BudgetAmount float64
	Currency     string
	Status       string
}
