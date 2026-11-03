package agents

import (
	"regexp"
	"strings"
	"testing"

	"github.com/SmartFin-App/smartfin-backend/internal/models"
)

func TestFunctionDeclarations(t *testing.T) {
	orch := &Orchestrator{}
	decls := orch.getFunctionDeclarations()

	expectedTools := map[string]bool{
		"web_search":               false,
		"update_budget_limit":      false,
		"add_transaction":          false,
		"get_budget_summary":       false,
		"get_transactions":         false,
		"get_recent_conversations": false,
		"get_subscriptions":        false,
		"get_spending_insights":    false,
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

// When no search backend answers, the coach must get no figures at all: the old
// canned fallback supplied a policy rate the model then presented as current.
func TestSearchUnavailableCarriesNoFigures(t *testing.T) {
	query := "What is the Bank of Thailand interest rate?"
	res := searchUnavailable(query)

	if res["query"] != query {
		t.Errorf("query not echoed back: %v", res["query"])
	}
	if res["available"] != false {
		t.Errorf("must be marked unavailable so the model can tell it from a result: %v", res["available"])
	}
	if results, _ := res["results"].([]any); len(results) != 0 {
		t.Errorf("must return no results, got %v", results)
	}

	note, _ := res["note"].(string)
	if note == "" {
		t.Fatal("must tell the model what to do instead")
	}
	// Any percentage or amount would be a figure the model could repeat as fact.
	if m := regexp.MustCompile(`\d+(\.\d+)?\s*%|\d{1,3}(,\d{3})+`).FindString(note); m != "" {
		t.Errorf("note must not contain a figure, found %q", m)
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

// A missing profile, or a missing value within one, must never be filled in: the
// coach used to be told an unknown user earned ฿30,000 with a ฿15,000 budget.
func TestDescribeProfileNeverInventsFigures(t *testing.T) {
	missing := describeProfile(models.User{}, false)
	if strings.Contains(missing, "฿") {
		t.Errorf("a missing profile must carry no amounts: %q", missing)
	}
	if !strings.Contains(missing, "not set up") {
		t.Errorf("a missing profile must say so: %q", missing)
	}

	// A real profile with no budget: zero is "not set", never ฿0.
	empty := describeProfile(models.User{Name: "Ploy"}, true)
	if strings.Contains(empty, "฿0") || !strings.Contains(empty, "Monthly Budget Limit: not set") {
		t.Errorf("an unset budget must read as not set: %q", empty)
	}

	full := describeProfile(models.User{Name: "Ploy", BudgetLimit: 15000}, true)
	if !strings.Contains(full, "Monthly Budget Limit: ฿15000") {
		t.Errorf("want the budget in %q", full)
	}
}

// SmartFin tracks spending only, so the coach must never be handed an income or a
// savings figure to repeat.
func TestDescribeProfileHasNoIncomeOrSavings(t *testing.T) {
	p := strings.ToLower(describeProfile(models.User{Name: "Ploy", BudgetLimit: 15000}, true))
	for _, word := range []string{"income", "saving"} {
		if strings.Contains(p, word) {
			t.Errorf("profile must not mention %q: %q", word, p)
		}
	}
}
