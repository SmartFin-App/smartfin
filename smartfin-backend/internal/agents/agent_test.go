package agents

import (
	"context"
	"testing"
	"time"
)

func TestFunctionDeclarations(t *testing.T) {
	orch := &Orchestrator{}
	decls := orch.getFunctionDeclarations()

	expectedTools := map[string]bool{
		"web_search":                 false,
		"set_savings_goal":           false,
		"update_budget_limit":        false,
		"add_transaction":            false,
		"get_budget_summary":         false,
		"get_transactions":           false,
		"get_recent_conversations":   false,
		"detect_spending_anomalies":  false,
	}

	for _, d := range decls {
		if _, exists := expectedTools[d.Name]; exists {
			expectedTools[d.Name] = true
		} else {
			t.Errorf("Unexpected tool declared: %s", d.Name)
		}
	}

	for tool, found := range expectedTools {
		if !found {
			t.Errorf("Expected tool %s was not found in function declarations", tool)
		}
	}

	if len(decls) != 8 {
		t.Errorf("Expected 8 declared tools, got %d", len(decls))
	}
}

func TestResearchAgentWebSearchFallback(t *testing.T) {
	agent := NewResearchAgent()

	query := "What is the Bank of Thailand interest rate?"
	fallback := agent.getFinancialFallback(query)
	if fallback == "" {
		t.Fatalf("Expected non-empty fallback for financial query")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()

	res, err := agent.WebSearch(ctx, query)
	if err != nil {
		t.Fatalf("WebSearch returned unexpected error: %v", err)
	}

	if res["query"] != query {
		t.Errorf("Expected query to match in result, got %v", res["query"])
	}
}
