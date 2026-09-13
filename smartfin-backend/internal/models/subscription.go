package models

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// Subscription is a recurring payment the user tracks by hand — a streaming plan,
// a phone bill, rent. It is a reminder, not a record of spending: paying one
// creates an ordinary expense transaction and moves NextDueDate forward a cycle.
type Subscription struct {
	ID           bson.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID       string        `bson:"user_id" json:"user_id"`
	Name         string        `bson:"name" json:"name"`
	Amount       int64         `bson:"amount" json:"amount"`
	BillingCycle string        `bson:"billing_cycle" json:"billing_cycle"`
	// NextDueDate is midnight, Thai time, of the due day. Clients should read the
	// response's due_date string instead of converting this instant themselves.
	NextDueDate time.Time `bson:"next_due_date" json:"next_due_date"`
	// AnchorDay is the day of the month the bill is due on, so a bill due on the
	// 31st returns to the 31st after being clamped to a shorter month.
	AnchorDay  int        `bson:"anchor_day" json:"anchor_day"`
	Category   string     `bson:"category" json:"category"`
	Note       string     `bson:"note" json:"note"`
	Active     bool       `bson:"active" json:"active"`
	LastPaidAt *time.Time `bson:"last_paid_at,omitempty" json:"last_paid_at,omitempty"`
	CreatedAt  time.Time  `bson:"created_at" json:"created_at"`
	UpdatedAt  time.Time  `bson:"updated_at" json:"updated_at"`
}

// UpdateSubscriptionRequest is a partial update. Pointer fields keep "absent"
// distinguishable from "set to false/empty", so pausing a bill or clearing its
// note is a real write rather than a no-op.
type UpdateSubscriptionRequest struct {
	Name         *string `json:"name"`
	Amount       *int64  `json:"amount"`
	BillingCycle *string `json:"billing_cycle"`
	NextDueDate  *string `json:"next_due_date"`
	Category     *string `json:"category"`
	Note         *string `json:"note"`
	Active       *bool   `json:"active"`
}

// ToUpdateFields returns the fields to $set. NextDueDate is deliberately left
// out: the handler parses it in Thai time and sets anchor_day alongside it.
func (r UpdateSubscriptionRequest) ToUpdateFields() map[string]any {
	fields := map[string]any{}
	if r.Name != nil {
		fields["name"] = *r.Name
	}
	if r.Amount != nil {
		fields["amount"] = *r.Amount
	}
	if r.BillingCycle != nil {
		fields["billing_cycle"] = *r.BillingCycle
	}
	if r.Category != nil {
		fields["category"] = *r.Category
	}
	if r.Note != nil {
		fields["note"] = *r.Note
	}
	if r.Active != nil {
		fields["active"] = *r.Active
	}
	return fields
}

// SubscriptionResponse adds everything a client needs to display a bill without
// doing date math of its own — the device clock may not be on Thai time.
type SubscriptionResponse struct {
	Subscription      `bson:",inline"`
	DueDate           string `json:"due_date"`           // "2026-09-14", Thai calendar day
	DaysUntilDue      int    `json:"days_until_due"`     // negative when overdue
	Status            string `json:"status"`             // paused | overdue | due_today | due_soon | upcoming
	FormattedAmount   string `json:"formatted_amount"`   // "฿1,990"
	FormattedDueDate  string `json:"formatted_due_date"` // Today | Tomorrow | Yesterday | "Oct 14"
	MonthlyEquivalent int64  `json:"monthly_equivalent"`
	// NextDueAfterPayment previews where "Mark paid" moves the due date.
	NextDueAfterPayment string `json:"next_due_after_payment"`
}
