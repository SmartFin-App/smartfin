package models

import "testing"

func strPtr(s string) *string { return &s }
func i64Ptr(i int64) *int64   { return &i }

func TestToUpdateFieldsOmitsAbsentFields(t *testing.T) {
	req := UpdateUserRequest{BudgetLimit: i64Ptr(15000)}
	fields := req.ToUpdateFields()

	if len(fields) != 1 {
		t.Fatalf("expected only the populated field, got %v", fields)
	}
	if fields["budget_limit"] != int64(15000) {
		t.Errorf("budget_limit = %v (%T), want int64(15000)", fields["budget_limit"], fields["budget_limit"])
	}
	if _, present := fields["monthly_income"]; present {
		t.Error("an absent field must not appear in the update document")
	}
}

// Clearing a savings goal writes 0 and empty strings. If absent and zero were
// conflated, "remove goal" would silently do nothing.
func TestToUpdateFieldsKeepsExplicitZeroes(t *testing.T) {
	req := UpdateUserRequest{
		SavingsGoal:       i64Ptr(0),
		SavingsGoalName:   strPtr(""),
		SavingsTargetDate: strPtr(""),
	}
	fields := req.ToUpdateFields()

	if len(fields) != 3 {
		t.Fatalf("expected all three cleared fields, got %v", fields)
	}
	if fields["savings_goal"] != int64(0) {
		t.Errorf("savings_goal = %v, want int64(0)", fields["savings_goal"])
	}
	if fields["savings_goal_name"] != "" {
		t.Errorf("savings_goal_name = %q, want empty string", fields["savings_goal_name"])
	}
}

func TestToUpdateFieldsIsEmptyForAnEmptyRequest(t *testing.T) {
	if fields := (UpdateUserRequest{}).ToUpdateFields(); len(fields) != 0 {
		t.Errorf("empty request produced %v, want no fields", fields)
	}
}

// Money must not degrade to float64 on the way to Mongo, or the same field ends up
// stored as a double for edited users and an int64 for newly created ones.
func TestToUpdateFieldsKeepsMoneyAsInt64(t *testing.T) {
	req := UpdateUserRequest{
		MonthlyIncome: i64Ptr(60000),
		BudgetLimit:   i64Ptr(42000),
		SavingsGoal:   i64Ptr(50000),
	}
	for field, want := range map[string]int64{
		"monthly_income": 60000,
		"budget_limit":   42000,
		"savings_goal":   50000,
	} {
		got, ok := req.ToUpdateFields()[field].(int64)
		if !ok {
			t.Errorf("%s is %T, want int64", field, req.ToUpdateFields()[field])
			continue
		}
		if got != want {
			t.Errorf("%s = %d, want %d", field, got, want)
		}
	}
}

// The names must match what the coach's action agent writes directly to Mongo,
// or a goal set in the app and one set by the coach land in different fields.
func TestToUpdateFieldsUsesTheSameKeysAsTheCoach(t *testing.T) {
	req := UpdateUserRequest{
		SavingsGoal:       i64Ptr(50000),
		SavingsGoalName:   strPtr("Japan Trip"),
		SavingsTargetDate: strPtr("2026-12-31"),
		BudgetLimit:       i64Ptr(20000),
	}
	fields := req.ToUpdateFields()
	for _, key := range []string{"savings_goal", "savings_goal_name", "savings_target_date", "budget_limit"} {
		if _, ok := fields[key]; !ok {
			t.Errorf("missing key %q that the action agent also writes", key)
		}
	}
}
