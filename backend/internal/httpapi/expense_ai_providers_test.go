package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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

func TestCompactExpenseAIModelItemsRespectsPromptBudget(t *testing.T) {
	items := make([]CostItemDTO, 0, 300)
	for i := 0; i < 300; i++ {
		items = append(items, CostItemDTO{
			ID:          fmt.Sprintf("expense-%d", i),
			Title:       strings.Repeat("long title ", 40),
			Description: strings.Repeat("long description ", 100),
			Vendor:      strings.Repeat("vendor ", 40),
			Amount:      100,
			Currency:    "KGS",
		})
	}

	compact := compactExpenseAIModelItems(items)
	encoded, err := json.Marshal(compact)
	if err != nil {
		t.Fatalf("json.Marshal returned error: %v", err)
	}
	if len(encoded) > maxExpenseAIPromptBytes {
		t.Fatalf("compact AI payload is too large: %d bytes", len(encoded))
	}
	if len(compact) == 0 || len(compact) >= len(items) {
		t.Fatalf("expected a non-empty compacted subset, got %d of %d", len(compact), len(items))
	}
}
