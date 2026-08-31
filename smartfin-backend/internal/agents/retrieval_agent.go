package agents

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type RetrievalAgent struct {
	transactionsCollection *mongo.Collection
	usersCollection        *mongo.Collection
	summariesCollection    *mongo.Collection
}

func NewRetrievalAgent() *RetrievalAgent {
	return &RetrievalAgent{
		transactionsCollection: config.GetCollection("transactions"),
		usersCollection:        config.GetCollection("users"),
		summariesCollection:    config.GetCollection("monthly_summaries"),
	}
}

// GetUserContext fetches the user profile and builds a context string
func (a *RetrievalAgent) GetUserContext(ctx context.Context, userID string) string {
	var user models.User
	err := a.usersCollection.FindOne(ctx, bson.M{"firebase_uid": userID}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			log.Printf("User profile not found for coach: %v (using default profile)", err)
			user = models.User{
				Name:            "SmartFin User",
				MonthlyIncome:   30000,
				IncomeBracket:   "Medium",
				CurrentStatus:   "Balanced",
				FinancialHealth: "Growth",
				BudgetLimit:     15000,
			}
		} else {
			log.Printf("Error fetching user: %v", err)
			return "User Profile: Error fetching user data."
		}
	}

	return fmt.Sprintf(`User Profile:
- Name: %s
- Monthly Income: ฿%d
- Income Bracket: %s
- Current Status: %s
- Financial Health Goal: %s
- Budget Limit: ฿%d`,
		user.Name, user.MonthlyIncome, user.IncomeBracket,
		user.CurrentStatus, user.FinancialHealth, user.BudgetLimit,
	)
}

// GetTransactionContext fetches the last 50 transactions and builds a context string
func (a *RetrievalAgent) GetTransactionContext(ctx context.Context, userID string) string {
	opts := options.Find().SetSort(bson.D{{Key: "date", Value: -1}}).SetLimit(50)
	cursor, err := a.transactionsCollection.Find(ctx, bson.M{"user_id": userID}, opts)
	if err != nil {
		log.Printf("Error fetching transactions for coach: %v", err)
		return "User's recent transactions: Error fetching data."
	}
	defer cursor.Close(ctx)

	var transactions []models.Transaction
	if err := cursor.All(ctx, &transactions); err != nil {
		return "User's recent transactions: Error decoding data."
	}

	var transactionContext strings.Builder
	transactionContext.WriteString("User's recent transactions:\n")
	if len(transactions) == 0 {
		transactionContext.WriteString("- No transactions recorded yet.\n")
	} else {
		for _, t := range transactions {
			transactionContext.WriteString(fmt.Sprintf(
				"- %s: %s ฿%d (%s) on %s\n",
				t.Type, t.Merchant, t.Amount, t.Category, t.Date.Format("Jan 2, 2006"),
			))
		}
	}

	return transactionContext.String()
}

// GetSummaryContext fetches the last 6 months summary history and builds a context string
func (a *RetrievalAgent) GetSummaryContext(ctx context.Context, userID string) string {
	var summaryContext strings.Builder
	summaryContext.WriteString("\nMonthly Summary History (last 6 months):\n")

	now := time.Now()
	for i := 0; i < 6; i++ {
		targetDate := now.AddDate(0, -i, 0)
		month := fmt.Sprintf("%d-%02d", targetDate.Year(), targetDate.Month())
		
		var summary models.MonthlySummary
		err := a.summariesCollection.FindOne(ctx, bson.M{"user_id": userID, "month": month}).Decode(&summary)
		if err != nil {
			continue
		}
		
		summaryContext.WriteString(fmt.Sprintf(
			"- %s: Income ฿%d, Expenses ฿%d, Available ฿%d, Budget Used %.1f%%\n",
			month, summary.TotalIncome, summary.TotalExpenses,
			summary.Available, summary.BudgetPercentage,
		))
		for _, cat := range summary.ExpenseByCategory {
			summaryContext.WriteString(fmt.Sprintf(
				"  • %s: ฿%d (%.1f%%)\n",
				cat.Category, cat.Amount, cat.Percentage,
			))
		}
	}

	return summaryContext.String()
}
