package httpapi

import (
	"context"
	"errors"
	"testing"
)

func TestRunExpenseAIProvidersFallsBackAfterFailure(t *testing.T) {
	providers := []expenseAIProviderConfig{
		{name: "primary", model: "primary-model", apiKey: "primary-key"},
		{name: "backup", model: "backup-model", apiKey: "backup-key"},
	}
	called := make([]string, 0, len(providers))
	result := expenseAIModelResponse{SelectedIDs: []string{"expense-2"}, Summary: "backup"}

	got, provider, model, err := runExpenseAIProviders(
		context.Background(),
		"крыша",
		nil,
		providers,
		func(_ context.Context, provider expenseAIProviderConfig, _ string, _ []CostItemDTO) (expenseAIModelResponse, error) {
			called = append(called, provider.name)
			if provider.name == "primary" {
				return expenseAIModelResponse{}, errors.New("rate limited")
			}
			return result, nil
		},
	)

	if err != nil {
		t.Fatalf("runExpenseAIProviders returned error: %v", err)
	}
	if provider != "backup" || model != "backup-model" {
		t.Fatalf("expected backup provider, got provider=%q model=%q", provider, model)
	}
	if len(called) != 2 || called[0] != "primary" || called[1] != "backup" {
		t.Fatalf("unexpected provider call order: %#v", called)
	}
	if len(got.SelectedIDs) != 1 || got.SelectedIDs[0] != "expense-2" {
		t.Fatalf("unexpected result: %#v", got)
	}
}

func TestRunExpenseAIProvidersReturnsLastErrorWhenAllFail(t *testing.T) {
	providers := []expenseAIProviderConfig{
		{name: "primary", model: "primary-model", apiKey: "primary-key"},
		{name: "backup", model: "backup-model", apiKey: "backup-key"},
	}

	_, _, _, err := runExpenseAIProviders(
		context.Background(),
		"крыша",
		nil,
		providers,
		func(_ context.Context, provider expenseAIProviderConfig, _ string, _ []CostItemDTO) (expenseAIModelResponse, error) {
			return expenseAIModelResponse{}, errors.New(provider.name + " failed")
		},
	)
	if err == nil || err.Error() != "backup: backup failed" {
		t.Fatalf("expected last provider error, got %v", err)
	}
}

func TestParseExpenseAISelectionAllowsFencedJSON(t *testing.T) {
	result, err := parseExpenseAISelection("```json\n{\"selected_ids\":[\"id-1\"],\"summary\":\"материалы\"}\n```")
	if err != nil {
		t.Fatalf("parseExpenseAISelection returned error: %v", err)
	}
	if len(result.SelectedIDs) != 1 || result.SelectedIDs[0] != "id-1" || result.Summary != "материалы" {
		t.Fatalf("unexpected selection: %#v", result)
	}
}
