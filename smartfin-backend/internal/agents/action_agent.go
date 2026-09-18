package agents

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

// ActionAgent executes state-modifying financial actions in MongoDB Atlas
type ActionAgent struct {
	usersCol        *mongo.Collection
	transactionsCol *mongo.Collection
	summariesCol    *mongo.Collection
}

// NewActionAgent creates a new FinancialActionAgent
func NewActionAgent() *ActionAgent {
	return &ActionAgent{
		usersCol:        config.GetCollection("users"),
		transactionsCol: config.GetCollection("transactions"),
		summariesCol:    config.GetCollection("monthly_summaries"),
	}
}

// UpdateBudgetLimit updates the monthly budget limit on the user's profile
func (a *ActionAgent) UpdateBudgetLimit(ctx context.Context, userID string, budgetLimit int64) (map[string]any, error) {
	if budgetLimit <= 0 {
		return nil, fmt.Errorf("budget limit must be greater than 0")
	}

	update := bson.M{
		"$set": bson.M{
			"budget_limit": budgetLimit,
			"updated_at":   time.Now(),
		},
	}

	_, err := a.usersCol.UpdateOne(ctx, bson.M{"firebase_uid": userID}, update)
	if err != nil {
		return nil, fmt.Errorf("failed to update budget limit: %w", err)
	}

	// Invalidate rather than patch the single field: patching budget_limit in place
	// left budget_percentage computed against the old limit, so the coach quoted a
	// percentage that did not match the limit it had just set.
	summaries.Invalidate(ctx, a.summariesCol, userID, summaries.StringOf(time.Now()))

	log.Printf("ActionAgent: UpdateBudgetLimit for user %s to ฿%d", userID, budgetLimit)

	return map[string]any{
		"status":       "success",
		"action":       "update_budget_limit",
		"budget_limit": budgetLimit,
		"message":      fmt.Sprintf("Successfully updated monthly budget limit to ฿%d", budgetLimit),
	}, nil
}

// AddTransaction records an expense in MongoDB and marks the month's summary
// dirty. Expenses only: SmartFin tracks spending, and an income record would be
// hidden everywhere the user could see it.
func (a *ActionAgent) AddTransaction(ctx context.Context, userID, merchant string, amount int64, category, dateStr string) (map[string]any, error) {
	if merchant == "" {
		merchant = "Unknown Merchant"
	}
	if amount <= 0 {
		return nil, fmt.Errorf("transaction amount must be greater than 0")
	}
	if category == "" {
		category = "General"
	}

	txDate := time.Now()
	if dateStr != "" {
		// Try parsing common date formats
		formats := []string{"2006-01-02", "2006/01/02", "02-01-2006", "02/01/2006", time.RFC3339}
		parsedOK := false
		for _, f := range formats {
			if parsed, err := time.Parse(f, dateStr); err == nil {
				txDate = parsed
				parsedOK = true
				break
			}
		}
		if !parsedOK {
			// Reporting this lets the model retry with a real date rather than
			// having the transaction silently filed under today.
			return nil, fmt.Errorf("could not parse date %q, use YYYY-MM-DD", dateStr)
		}
	}

	now := time.Now()
	tx := models.Transaction{
		ID:        bson.NewObjectID(),
		UserID:    userID,
		Merchant:  merchant,
		Amount:    amount,
		Type:      "expense",
		Category:  category,
		Source:    "coach_agent",
		Date:      txDate,
		CreatedAt: now,
		UpdatedAt: now,
	}

	_, err := a.transactionsCol.InsertOne(ctx, tx)
	if err != nil {
		return nil, fmt.Errorf("failed to insert transaction: %w", err)
	}

	// Drop the cached summary for that month so the next retrieval recomputes it.
	// This must not spare frozen months: a backdated entry is exactly the case that
	// used to stay invisible to every total while still showing in the list.
	summaries.InvalidateFor(ctx, a.summariesCol, userID, txDate)

	log.Printf("ActionAgent: AddTransaction for user %s: expense ฿%d (%s) on %s", userID, amount, merchant, txDate.Format("2006-01-02"))

	return map[string]any{
		"status":   "success",
		"action":   "add_transaction",
		"id":       tx.ID.Hex(),
		"merchant": merchant,
		"amount":   amount,
		"type":     "expense",
		"category": category,
		"date":     txDate.Format("2006-01-02"),
		"message":  fmt.Sprintf("Successfully recorded an expense of ฿%d at %s (%s)", amount, merchant, category),
	}, nil
}
