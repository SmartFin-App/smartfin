package models

import (
	"errors"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
)

// Transaction represents a MongoDB document in the transactions collection
type Transaction struct {
	ID              bson.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID          string        `bson:"user_id" json:"user_id"`
	Merchant        string        `bson:"merchant" json:"merchant"`
	Amount          int64         `bson:"amount" json:"amount"`
	Type            string        `bson:"type" json:"type"`
	Category        string        `bson:"category" json:"category"`
	Source          string        `bson:"source" json:"source"`
	ReceiptImageURL string        `bson:"receipt_image_url" json:"receipt_image_url"`
	Date            time.Time     `bson:"date" json:"date"`
	// Set only when the slip was shared: Amount is then the user's own share,
	// SplitTotal what the slip was for and SplitPeople how many shared it
	// (the user included). Totals and budgets read Amount alone.
	SplitTotal  int64     `bson:"split_total,omitempty" json:"split_total,omitempty"`
	SplitPeople int       `bson:"split_people,omitempty" json:"split_people,omitempty"`
	CreatedAt   time.Time `bson:"created_at" json:"created_at"`
	UpdatedAt   time.Time `bson:"updated_at" json:"updated_at"`
}

// MaxSplitPeople bounds a split's head count; it is a sanity limit, not a rule
// about how bills are shared.
const MaxSplitPeople = 100

// ValidateSplit checks the split note sent with a new expense. Both zero means
// the expense was not split. Otherwise the share cannot exceed the slip it came
// from, and a split needs at least one other person.
func ValidateSplit(amount, splitTotal int64, splitPeople int) error {
	if splitTotal == 0 && splitPeople == 0 {
		return nil
	}
	if splitTotal <= 0 || splitPeople == 0 {
		return errors.New("split_total and split_people must be sent together")
	}
	if splitPeople < 2 || splitPeople > MaxSplitPeople {
		return errors.New("split_people must be between 2 and 100")
	}
	if amount > splitTotal {
		return errors.New("amount cannot be more than split_total")
	}
	return nil
}

// CreateTransactionRequest represents the API request body when creating a transaction
type CreateTransactionRequest struct {
	Merchant string `json:"merchant"`
	Amount   int64  `json:"amount"`
	Type     string `json:"type"`
	Category string `json:"category"`
	Source   string `json:"source"`
	Date     string `json:"date"`
}

// UpdateTransactionRequest represents the API request body when editing a transaction
type UpdateTransactionRequest struct {
	Merchant *string `json:"merchant"`
	Amount   *int64  `json:"amount"`
	Type     *string `json:"type"`
	Category *string `json:"category"`
	Source   *string `json:"source"`
	Date     *string `json:"date"`
}

// TransactionResponse is what we send back to Flutter
type TransactionResponse struct {
	Transaction     `bson:",inline"` // Embedded fields from Transaction
	FormattedAmount string           `json:"formatted_amount"`
	FormattedDate   string           `json:"formatted_date"`
}

// ExpenseCategories are the categories the app offers, spelled as it stores them.
var ExpenseCategories = []string{
	"Food", "Transport", "Groceries", "Shopping", "Bills", "Health", "Entertainment", "Other",
}

// NormalizeCategory maps a model-written category onto one the app offers,
// ignoring case and surrounding space. Anything else becomes "Other", so an
// invented name like "Healthcare" never reaches the client as a category.
func NormalizeCategory(raw string) string {
	raw = strings.TrimSpace(raw)
	for _, c := range ExpenseCategories {
		if strings.EqualFold(raw, c) {
			return c
		}
	}
	return "Other"
}
