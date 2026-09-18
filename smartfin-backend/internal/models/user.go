package models

import (
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// User represents a MongoDB document in the users collection
type User struct {
	ID              bson.ObjectID `bson:"_id,omitempty" json:"id"`
	FirebaseUID     string        `bson:"firebase_uid" json:"firebase_uid"`
	Name            string        `bson:"name" json:"name"`
	Email           string        `bson:"email" json:"email"`
	PhotoURL        string        `bson:"photo_url" json:"photo_url"`
	CurrentStatus   string        `bson:"current_status" json:"current_status"`
	FinancialHealth string        `bson:"financial_health" json:"financial_health"`
	BudgetLimit     int64         `bson:"budget_limit" json:"budget_limit"`
	CreatedAt       time.Time     `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time     `bson:"updated_at" json:"updated_at"`
}

// UpdateUserRequest is the API request body for a partial profile update.
//
// Every field is a pointer so "absent" and "set to zero" stay distinguishable —
// clearing a value has to be a real write, not a no-op. Binding to this instead of
// a bare map means money arrives as int64 rather than a JSON float64 that lands in
// Mongo as a double, and an unknown key — including the monthly_income and
// savings_goal fields this app no longer has — is ignored rather than being $set
// into the document verbatim.
type UpdateUserRequest struct {
	Name            *string `json:"name"`
	Email           *string `json:"email"`
	PhotoURL        *string `json:"photo_url"`
	CurrentStatus   *string `json:"current_status"`
	FinancialHealth *string `json:"financial_health"`
	BudgetLimit     *int64  `json:"budget_limit"`
}

// ToUpdateFields renders the populated fields as a BSON $set document, keyed by the
// same names the coach's action agent writes directly.
func (r UpdateUserRequest) ToUpdateFields() map[string]any {
	fields := map[string]any{}
	if r.Name != nil {
		fields["name"] = *r.Name
	}
	if r.Email != nil {
		fields["email"] = *r.Email
	}
	if r.PhotoURL != nil {
		fields["photo_url"] = *r.PhotoURL
	}
	if r.CurrentStatus != nil {
		fields["current_status"] = *r.CurrentStatus
	}
	if r.FinancialHealth != nil {
		fields["financial_health"] = *r.FinancialHealth
	}
	if r.BudgetLimit != nil {
		fields["budget_limit"] = *r.BudgetLimit
	}
	return fields
}

// CreateUserRequest represents the API request body when creating a user
type CreateUserRequest struct {
	FirebaseUID     string `json:"firebase_uid"`
	Name            string `json:"name"`
	Email           string `json:"email"`
	PhotoURL        string `json:"photo_url"`
	CurrentStatus   string `json:"current_status"`
	FinancialHealth string `json:"financial_health"`
	BudgetLimit     int64  `json:"budget_limit"`
}
