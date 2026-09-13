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
		"web_search":               false,
		"set_savings_goal":         false,
		"update_budget_limit":      false,
		"add_transaction":          false,
		"get_budget_summary":       false,
		"get_transactions":         false,
		"get_recent_conversations": false,
		"get_subscriptions":        false,
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

func TestLooksLikeStall(t *testing.T) {
	stalls := []string{
		"🐾 To figure out how much you saved in March 2026, I'll need to look at your income and expenses for that month. Please give me a moment to fetch that information for you!",
		"🐾 ได้เลยค่ะ! ขอตรวจสอบค่าใช้จ่ายหมวดอาหารของคุณสำหรับเดือนมีนาคม 2026 ให้นะคะ",
		"🐾 เข้าใจแล้วค่ะ! กำลังตรวจสอบบิลที่เลยกำหนดชำระให้นะคะ",
	}
	for _, s := range stalls {
		if !looksLikeStall(s) {
			t.Errorf("should be treated as a stall: %q", s)
		}
	}
	answers := []string{
		"You spent ฿1,300 on Food in March 2026 🐾",
		"That's an interesting coding challenge! However, as your SmartFin Coach, my paw-some purpose is to help you with your financial well-being. 🐾",
		"Your monthly budget limit is ฿15,000.",
		"",
	}
	for _, s := range answers {
		if looksLikeStall(s) {
			t.Errorf("a real answer must not be nudged: %q", s)
		}
	}
}
