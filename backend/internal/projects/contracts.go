package projects

type Project struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Status string `json:"status"`
}

type CreateProjectRequest struct {
	Name string `json:"name"`
}

type Repository interface {
	Create(ownerID string, req CreateProjectRequest) (Project, error)
	List(ownerID string) ([]Project, error)
}
