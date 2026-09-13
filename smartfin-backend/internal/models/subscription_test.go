package models

import "testing"

func boolPtr(b bool) *bool { return &b }

func TestSubscriptionUpdateOmitsAbsentFields(t *testing.T) {
	fields := UpdateSubscriptionRequest{Amount: i64Ptr(599)}.ToUpdateFields()

	if len(fields) != 1 {
		t.Fatalf("expected only the populated field, got %v", fields)
	}
	if got, ok := fields["amount"].(int64); !ok || got != 599 {
		t.Errorf("amount = %v (%T), want int64(599)", fields["amount"], fields["amount"])
	}
}

// Pausing a bill writes false and clearing a note writes "". Conflating those with
// "absent" would make both silently do nothing.
func TestSubscriptionUpdateKeepsExplicitFalseAndEmpty(t *testing.T) {
	fields := UpdateSubscriptionRequest{Active: boolPtr(false), Note: strPtr("")}.ToUpdateFields()

	if len(fields) != 2 {
		t.Fatalf("expected both fields, got %v", fields)
	}
	if fields["active"] != false {
		t.Errorf("active = %v, want false", fields["active"])
	}
	if fields["note"] != "" {
		t.Errorf("note = %q, want empty string", fields["note"])
	}
}

// The due date has to be parsed in Thai time and paired with anchor_day, which
// only the handler does — a raw string must never reach Mongo.
func TestSubscriptionUpdateLeavesTheDueDateToTheHandler(t *testing.T) {
	fields := UpdateSubscriptionRequest{NextDueDate: strPtr("2026-10-01")}.ToUpdateFields()
	if len(fields) != 0 {
		t.Errorf("next_due_date leaked into the update: %v", fields)
	}
}

func TestSubscriptionUpdateIsEmptyForAnEmptyRequest(t *testing.T) {
	if fields := (UpdateSubscriptionRequest{}).ToUpdateFields(); len(fields) != 0 {
		t.Errorf("empty request produced %v, want no fields", fields)
	}
}
