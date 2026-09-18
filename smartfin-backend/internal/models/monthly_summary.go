package models

import (
	"go.mongodb.org/mongo-driver/v2/bson"
	"time"
)

// CategorySummary holds spending totals for a single expense category
type CategorySummary struct {
	Category   string  `bson:"category"   json:"category"`
	Amount     int64   `bson:"amount"     json:"amount"`
	Percentage float64 `bson:"percentage" json:"percentage"` // % of total expenses
}

// MonthlySummary is stored in MongoDB and is a user's spending snapshot for one
// month: what they spent, by category, against their budget.
//
// Income used to live here too — a monthly salary from the profile credited in
// full on day one, plus "available" and "savings" derived from it. SmartFin now
// tracks spending only, so every figure here comes from expense transactions.
type MonthlySummary struct {
	ID                bson.ObjectID     `bson:"_id,omitempty"        json:"id"`
	UserID            string            `bson:"user_id"              json:"user_id"`
	Month             string            `bson:"month"                json:"month"`             // "2026-04"
	TotalExpenses     int64             `bson:"total_expenses"       json:"total_expenses"`    // sum of expense transactions
	BudgetLimit       int64             `bson:"budget_limit"         json:"budget_limit"`      // from user profile
	BudgetPercentage  float64           `bson:"budget_percentage"    json:"budget_percentage"` // total_expenses / budget_limit × 100
	ExpenseByCategory []CategorySummary `bson:"expense_by_category"  json:"expense_by_category"`
	IsFrozen          bool              `bson:"is_frozen"            json:"is_frozen"` // true when month has ended
	CalculatedAt      time.Time         `bson:"calculated_at"        json:"calculated_at"`
}

// MonthlySummaryResponse is the API response shape — extends MonthlySummary with UI helpers
type MonthlySummaryResponse struct {
	MonthlySummary
	FormattedMonth string          `json:"formatted_month"` // "April 2026"
	PreviousMonth  *MonthlySummary `json:"previous_month"`  // last month's snapshot for comparison
}
