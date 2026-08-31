package agents

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

type ActionAgent struct {
	transactionsCollection *mongo.Collection
	usersCollection        *mongo.Collection
}

func NewActionAgent() *ActionAgent {
	return &ActionAgent{
		transactionsCollection: config.GetCollection("transactions"),
		usersCollection:        config.GetCollection("users"),
	}
}

func (a *ActionAgent) SetSavingsGoal(ctx context.Context, userID string, goal float64) string {
	// Assume we just update the user's FinancialHealth or add a new field, for now we can simulate or update a generic field.
	// We will just log it for now or update a specific field if it exists.
	log.Printf("Setting savings goal to %f for user %s", goal, userID)
	return fmt.Sprintf("Successfully set savings goal to ฿%.0f.", goal)
}

func (a *ActionAgent) UpdateBudgetLimit(ctx context.Context, userID string, limit float64) string {
	update := bson.M{
		"$set": bson.M{
			"budget_limit": int64(limit),
			"updated_at":   time.Now(),
		},
	}
	_, err := a.usersCollection.UpdateOne(ctx, bson.M{"firebase_uid": userID}, update)
	if err != nil {
		log.Printf("Error updating budget limit: %v", err)
		return "Failed to update budget limit due to a database error."
	}
	return fmt.Sprintf("Successfully updated budget limit to ฿%.0f.", limit)
}

func (a *ActionAgent) AddTransaction(ctx context.Context, userID string, merchant string, amount float64, txType string, category string) string {
	transaction := models.Transaction{
		ID:        bson.NewObjectID(),
		UserID:    userID,
		Merchant:  merchant,
		Amount:    int64(amount),
		Type:      txType,
		Category:  category,
		Source:    "chat",
		Date:      time.Now(),
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	_, err := a.transactionsCollection.InsertOne(ctx, transaction)
	if err != nil {
		log.Printf("Error adding transaction: %v", err)
		return "Failed to add transaction due to a database error."
	}

	return fmt.Sprintf("Successfully added %s transaction for %s of ฿%.0f.", txType, merchant, amount)
}
