package agents

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// RetrievalAgent retrieves personal financial data from MongoDB Atlas
type RetrievalAgent struct {
	transactionsCol *mongo.Collection
	usersCol        *mongo.Collection
	summariesCol    *mongo.Collection
	chatMessagesCol *mongo.Collection
}

// NewRetrievalAgent creates a new FinancialRetrievalAgent
func NewRetrievalAgent() *RetrievalAgent {
	return &RetrievalAgent{
		transactionsCol: config.GetCollection("transactions"),
		usersCol:        config.GetCollection("users"),
		summariesCol:    config.GetCollection("monthly_summaries"),
		chatMessagesCol: config.GetCollection("chat_messages"),
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

	// Fallback calculation directly from transactions if summary record not yet generated
	now := time.Now()
	var parsedYear, parsedMonth int
	if _, err := fmt.Sscanf(month, "%d-%d", &parsedYear, &parsedMonth); err != nil {
		parsedYear = now.Year()
		parsedMonth = int(now.Month())
		month = fmt.Sprintf("%d-%02d", parsedYear, parsedMonth)
	}

	loc := time.UTC
	startOfMonth := time.Date(parsedYear, time.Month(parsedMonth), 1, 0, 0, 0, 0, loc)
	endOfMonth := startOfMonth.AddDate(0, 1, 0)

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
			"id":         t.ID.Hex(),
			"merchant":   t.Merchant,
			"amount":     t.Amount,
			"type":       t.Type,
			"category":   t.Category,
			"source":     t.Source,
			"date":       t.Date.Format("2006-01-02"),
			"date_human": t.Date.Format("Jan 02, 2006"),
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
			"role":       m.Role,
			"content":    m.Content,
			"timestamp":  m.CreatedAt.Format(time.RFC3339),
			"tool_calls": m.ToolCalls,
		})
	}
	return results, nil
}

// DetectSpendingAnomalies detects unusual transactions using an ML-service if configured,
// DetectSpendingAnomalies identifies unusual spending spikes or outliers using
// statistical Z-score outlier baseline per category.
func (a *RetrievalAgent) DetectSpendingAnomalies(ctx context.Context, userID string) (map[string]any, error) {
	// Statistical Anomaly Detection
	// Fetch last 100 expense transactions to build category statistics
	opts := options.Find().SetSort(bson.D{{Key: "date", Value: -1}}).SetLimit(100)
	cursor, err := a.transactionsCol.Find(ctx, bson.M{"user_id": userID, "type": "expense"}, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch transactions for anomaly detection: %w", err)
	}
	defer cursor.Close(ctx)

	var txs []models.Transaction
	if err := cursor.All(ctx, &txs); err != nil {
		return nil, fmt.Errorf("failed to decode transactions: %w", err)
	}

	if len(txs) < 3 {
		return map[string]any{
			"anomaly_count": 0,
			"anomalies":     []any{},
			"message":       "Not enough transaction data to detect spending anomalies yet.",
		}, nil
	}

	// Group amounts by category
	catAmounts := make(map[string][]float64)
	for _, t := range txs {
		cat := t.Category
		if cat == "" {
			cat = "General"
		}
		catAmounts[cat] = append(catAmounts[cat], float64(t.Amount))
	}

	// Compute mean and standard deviation per category
	type catStat struct {
		mean   float64
		stdDev float64
	}
	stats := make(map[string]catStat)
	for cat, vals := range catAmounts {
		var sum float64
		for _, v := range vals {
			sum += v
		}
		mean := sum / float64(len(vals))

		var varianceSum float64
		for _, v := range vals {
			diff := v - mean
			varianceSum += diff * diff
		}
		std := math.Sqrt(varianceSum / float64(len(vals)))
		stats[cat] = catStat{mean: mean, stdDev: std}
	}

	// Flag transactions that deviate significantly (> 2.2 stddev or > 2.5x category average)
	var anomalies []map[string]any
	for _, t := range txs {
		cat := t.Category
		if cat == "" {
			cat = "General"
		}
		s := stats[cat]
		amountF := float64(t.Amount)

		isOutlier := false
		var reason string

		if s.stdDev > 0 {
			zScore := (amountF - s.mean) / s.stdDev
			if zScore >= 2.2 && amountF > 1000 {
				isOutlier = true
				reason = fmt.Sprintf("Amount ฿%d is significantly higher than usual for %s (average: ฿%.0f, Z-score: %.1f)",
					t.Amount, cat, s.mean, zScore)
			}
		} else if amountF > s.mean*2.5 && amountF > 2000 {
			isOutlier = true
			reason = fmt.Sprintf("Amount ฿%d is more than 2.5x the typical spending in %s", t.Amount, cat)
		}

		if isOutlier {
			anomalies = append(anomalies, map[string]any{
				"id":         t.ID.Hex(),
				"merchant":   t.Merchant,
				"amount":     t.Amount,
				"category":   t.Category,
				"date":       t.Date.Format("2006-01-02"),
				"reason":     reason,
				"is_anomaly": true,
			})
		}
	}

	return map[string]any{
		"anomaly_count":    len(anomalies),
		"anomalies":        anomalies,
		"detection_method": "statistical_zscore",
	}, nil
}
