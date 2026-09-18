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
	if _, present := fields["name"]; present {
		t.Error("an absent field must not appear in the update document")
	}
}

// Clearing a budget writes 0. If absent and zero were conflated, "remove budget"
// would silently do nothing.
func TestToUpdateFieldsKeepsExplicitZeroes(t *testing.T) {
	req := UpdateUserRequest{
		BudgetLimit: i64Ptr(0),
		PhotoURL:    strPtr(""),
	}
	fields := req.ToUpdateFields()

	if len(fields) != 2 {
		t.Fatalf("expected both cleared fields, got %v", fields)
	}
	if fields["budget_limit"] != int64(0) {
		t.Errorf("budget_limit = %v, want int64(0)", fields["budget_limit"])
	}
	if fields["photo_url"] != "" {
		t.Errorf("photo_url = %q, want empty string", fields["photo_url"])
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
	req := UpdateUserRequest{BudgetLimit: i64Ptr(42000)}
	got, ok := req.ToUpdateFields()["budget_limit"].(int64)
	if !ok {
		t.Fatalf("budget_limit is %T, want int64", req.ToUpdateFields()["budget_limit"])
	}
	if got != 42000 {
		t.Errorf("budget_limit = %d, want 42000", got)
	}
}

// The key must match what the coach's action agent writes directly to Mongo, or a
// budget set in the app and one set by the coach land in different fields.
func TestToUpdateFieldsUsesTheSameKeyAsTheCoach(t *testing.T) {
	fields := UpdateUserRequest{BudgetLimit: i64Ptr(20000)}.ToUpdateFields()
	if _, ok := fields["budget_limit"]; !ok {
		t.Error(`missing key "budget_limit" that the action agent also writes`)
	}
}
