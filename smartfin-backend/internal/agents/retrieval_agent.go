package agents

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// RetrievalAgent retrieves personal financial data from MongoDB Atlas
type RetrievalAgent struct {
	transactionsCol  *mongo.Collection
	usersCol         *mongo.Collection
	summariesCol     *mongo.Collection
	chatMessagesCol  *mongo.Collection
	subscriptionsCol *mongo.Collection
}

// NewRetrievalAgent creates a new FinancialRetrievalAgent
func NewRetrievalAgent() *RetrievalAgent {
	return &RetrievalAgent{
		transactionsCol:  config.GetCollection("transactions"),
		usersCol:         config.GetCollection("users"),
		summariesCol:     config.GetCollection("monthly_summaries"),
		chatMessagesCol:  config.GetCollection("chat_messages"),
		subscriptionsCol: config.GetCollection("subscriptions"),
	}
}

// GetBudgetSummary retrieves the monthly financial summary for a user
func (a *RetrievalAgent) GetBudgetSummary(ctx context.Context, userID, month string) (map[string]any, error) {
	if month == "" || month == "current" {
		now := time.Now()
		month = fmt.Sprintf("%d-%02d", now.Year(), int(now.Month()))
	}

	// Fetch user profile for income / budget
	var user models.User
	_ = a.usersCol.FindOne(ctx, bson.M{"firebase_uid": userID}).Decode(&user)

	// Fetch or compute summary
	var summary models.MonthlySummary
	err := a.summariesCol.FindOne(ctx, bson.M{"user_id": userID, "month": month}).Decode(&summary)
	if err == nil {
		return map[string]any{
			"month":              summary.Month,
			"total_income":       summary.TotalIncome,
			"total_expenses":     summary.TotalExpenses,
			"available":          summary.Available,
			"budget_limit":       summary.BudgetLimit,
			"budget_percentage":  summary.BudgetPercentage,
			"savings":            summary.Savings,
			"category_breakdown": summary.ExpenseByCategory,
		}, nil
	}

	// Fallback calculation directly from transactions if summary record not yet
	// generated. The window comes from summaries.Bounds (+07:00), not a locally
	// computed UTC one: a UTC window put a 06:00 Bangkok expense in the previous
	// month, so the coach could quote a different total than the dashboard for
	// the very same month.
	startOfMonth, endOfMonth, err := summaries.Bounds(month)
	if err != nil {
		month = summaries.StringOf(time.Now())
		startOfMonth, endOfMonth, err = summaries.Bounds(month)
		if err != nil {
			return nil, fmt.Errorf("could not resolve month %q: %w", month, err)
		}
	}

	cursor, err := a.transactionsCol.Find(ctx, bson.M{
		"user_id": userID,
		"date": bson.M{
			"$gte": startOfMonth,
			"$lt":  endOfMonth,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("failed to query transactions: %w", err)
	}
	defer cursor.Close(ctx)

	var transactions []models.Transaction
	if err := cursor.All(ctx, &transactions); err != nil {
		return nil, fmt.Errorf("failed to decode transactions: %w", err)
	}

	var totalExpenses int64
	var oneTimeIncome int64
	catMap := make(map[string]int64)

	for _, t := range transactions {
		if t.Type == "expense" {
			totalExpenses += t.Amount
			cat := t.Category
			if cat == "" {
				cat = "General"
			}
			catMap[cat] += t.Amount
		} else if t.Type == "income" {
			oneTimeIncome += t.Amount
		}
	}

	totalIncome := user.MonthlyIncome + oneTimeIncome
	available := totalIncome - totalExpenses
	budgetPct := float64(0)
	if user.BudgetLimit > 0 {
		budgetPct = (float64(totalExpenses) / float64(user.BudgetLimit)) * 100
	}

	var breakdown []map[string]any
	for cat, amt := range catMap {
		pct := float64(0)
		if totalExpenses > 0 {
			pct = (float64(amt) / float64(totalExpenses)) * 100
		}
		breakdown = append(breakdown, map[string]any{
			"category":   cat,
			"amount":     amt,
			"percentage": math.Round(pct*10) / 10,
		})
	}
	sort.Slice(breakdown, func(i, j int) bool {
		return breakdown[i]["amount"].(int64) > breakdown[j]["amount"].(int64)
	})

	return map[string]any{
		"month":              month,
		"total_income":       totalIncome,
		"total_expenses":     totalExpenses,
		"available":          available,
		"budget_limit":       user.BudgetLimit,
		"budget_percentage":  math.Round(budgetPct*10) / 10,
		"savings":            int64(math.Max(0, float64(available))),
		"category_breakdown": breakdown,
	}, nil
}

// GetTransactions retrieves the user's transactions with optional filters
func (a *RetrievalAgent) GetTransactions(ctx context.Context, userID string, limit int, category, txType string) ([]map[string]any, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}

	filter := bson.M{"user_id": userID}
	if category != "" {
		filter["category"] = bson.M{"$regex": "^" + category, "$options": "i"}
	}
	if txType != "" {
		filter["type"] = txType
	}

	opts := options.Find().SetSort(bson.D{{Key: "date", Value: -1}}).SetLimit(int64(limit))
	cursor, err := a.transactionsCol.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query transactions: %w", err)
	}
	defer cursor.Close(ctx)

	var txs []models.Transaction
	if err := cursor.All(ctx, &txs); err != nil {
		return nil, fmt.Errorf("failed to decode transactions: %w", err)
	}

	var results []map[string]any
	for _, t := range txs {
		results = append(results, map[string]any{
			"id":       t.ID.Hex(),
			"merchant": t.Merchant,
			"amount":   t.Amount,
			"type":     t.Type,
			"category": t.Category,
			"source":   t.Source,
			// Rendered in Thai local time: a transaction stored at 17:30Z is the
			// next day for the user, and the model has no way to know that from
			// a UTC string.
			"date":       t.Date.In(summaries.Zone).Format("2006-01-02"),
			"date_human": t.Date.In(summaries.Zone).Format("Jan 02, 2006"),
		})
	}
	return results, nil
}

// GetRecentConversations retrieves the recent messages from MongoDB chat_messages collection
func (a *RetrievalAgent) GetRecentConversations(ctx context.Context, userID string, limit int) ([]map[string]any, error) {
	if limit <= 0 || limit > 20 {
		limit = 6
	}

	filter := bson.M{"user_id": userID}
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}}).SetLimit(int64(limit))
	cursor, err := a.chatMessagesCol.Find(ctx, filter, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query chat messages: %w", err)
	}
	defer cursor.Close(ctx)

	var messages []models.ChatMessage
	if err := cursor.All(ctx, &messages); err != nil {
		return nil, fmt.Errorf("failed to decode chat messages: %w", err)
	}

	// Reverse so chronological order
	var results []map[string]any
	for i := len(messages) - 1; i >= 0; i-- {
		m := messages[i]
		results = append(results, map[string]any{
			"role":    m.Role,
			"content": m.Content,
			// Same reason, and RFC3339 carries the +07:00 offset explicitly so the
			// model is never left guessing which zone it is reading.
			"timestamp":  m.CreatedAt.In(summaries.Zone).Format(time.RFC3339),
			"tool_calls": m.ToolCalls,
		})
	}
	return results, nil
}

// GetSubscriptions returns the user's active tracked bills that fall due within
// daysAhead days — overdue ones included — plus the monthly-equivalent total of
// every active bill. Read-only: paying a bill is done with "Mark paid" in the app,
// which also moves the due date, so the coach never books one itself.
func (a *RetrievalAgent) GetSubscriptions(ctx context.Context, userID string, daysAhead int) (map[string]any, error) {
	if daysAhead <= 0 {
		daysAhead = 30
	}
	if daysAhead > 366 {
		daysAhead = 366
	}

	opts := options.Find().SetSort(bson.D{{Key: "next_due_date", Value: 1}}).SetLimit(100)
	cursor, err := a.subscriptionsCol.Find(ctx, bson.M{"user_id": userID, "active": true}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to query subscriptions: %w", err)
	}
	defer cursor.Close(ctx)

	var subs []models.Subscription
	if err := cursor.All(ctx, &subs); err != nil {
		return nil, fmt.Errorf("failed to decode subscriptions: %w", err)
	}

	now := time.Now()
	bills := []map[string]any{}
	var monthlyTotal, windowTotal int64
	for _, s := range subs {
		monthlyTotal += summaries.MonthlyEquivalent(s.Amount, s.BillingCycle)
		days := summaries.DaysUntil(s.NextDueDate, now)
		if days > daysAhead {
			continue
		}
		windowTotal += s.Amount
		bills = append(bills, map[string]any{
			"id":                 s.ID.Hex(),
			"name":               s.Name,
			"amount":             s.Amount,
			"billing_cycle":      s.BillingCycle,
			"category":           s.Category,
			"note":               s.Note,
			"due_date":           summaries.DueDateString(s.NextDueDate),
			"due_date_human":     s.NextDueDate.In(summaries.Zone).Format("Jan 02, 2006"),
			"days_until_due":     days,
			"status":             summaries.DueStatus(days, true),
			"monthly_equivalent": summaries.MonthlyEquivalent(s.Amount, s.BillingCycle),
		})
	}

	return map[string]any{
		"today":               summaries.DueDateString(now),
		"days_ahead":          daysAhead,
		"active_count":        len(subs),
		"monthly_total":       monthlyTotal,
		"due_in_window_total": windowTotal,
		"bills":               bills,
	}, nil
}
