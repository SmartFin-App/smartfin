package handlers

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
)

// SummaryHandler handles monthly financial summary requests
type SummaryHandler struct {
	summariesCollection   *mongo.Collection
	transactionsCollection *mongo.Collection
	usersCollection       *mongo.Collection
}

// NewSummaryHandler creates a new SummaryHandler
func NewSummaryHandler() *SummaryHandler {
	return &SummaryHandler{
		summariesCollection:    config.GetCollection("monthly_summaries"),
		transactionsCollection: config.GetCollection("transactions"),
		usersCollection:        config.GetCollection("users"),
	}
}

// maxInt64 returns the larger of two int64 values
func maxInt64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

// calculateMonthlySummary computes a fresh MonthlySummary from transactions
func (h *SummaryHandler) calculateMonthlySummary(ctx context.Context, userID, month string) (*models.MonthlySummary, error) {
	var user models.User
	if err := h.usersCollection.FindOne(ctx, bson.M{"firebase_uid": userID}).Decode(&user); err != nil {
		if err == mongo.ErrNoDocuments {
			// New user without a profile yet - use defaults
			user = models.User{
				FirebaseUID:   userID,
				BudgetLimit:   0,
				MonthlyIncome: 0,
			}
		} else {
			return nil, fmt.Errorf("database error: %w", err)
		}
	}

	// Parse "2026-04" into start / end dates
	parts := strings.Split(month, "-")
	if len(parts) != 2 {
		return nil, fmt.Errorf("invalid month format: %s", month)
	}
	year, err := strconv.Atoi(parts[0])
	if err != nil {
		return nil, fmt.Errorf("invalid year: %w", err)
	}
	monthNum, err := strconv.Atoi(parts[1])
	if err != nil {
		return nil, fmt.Errorf("invalid month number: %w", err)
	}
	startDate := time.Date(year, time.Month(monthNum), 1, 0, 0, 0, 0, time.UTC)
	endDate := startDate.AddDate(0, 1, 0) // first day of the next month

	// Fetch all transactions for this user in this month
	filter := bson.M{
		"user_id": userID,
		"date": bson.M{
			"$gte": startDate,
			"$lt":  endDate,
		},
	}
	cursor, err := h.transactionsCollection.Find(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch transactions: %w", err)
	}
	defer cursor.Close(ctx)

	var transactions []models.Transaction
	if err := cursor.All(ctx, &transactions); err != nil {
		return nil, fmt.Errorf("failed to decode transactions: %w", err)
	}

	// Calculate income / expense totals and category breakdown
	var oneTimeIncome, totalExpenses int64
	categoryMap := make(map[string]int64)

	for _, t := range transactions {
		switch t.Type {
		case "income":
			oneTimeIncome += t.Amount
		case "expense":
			totalExpenses += t.Amount
			categoryMap[t.Category] += t.Amount
		}
	}

	// Build CategorySummary slice sorted by amount descending
	var categorySlice []models.CategorySummary
	for cat, amt := range categoryMap {
		pct := float64(0)
		if totalExpenses > 0 {
			pct = float64(amt) / float64(totalExpenses) * 100
		}
		categorySlice = append(categorySlice, models.CategorySummary{
			Category:   cat,
			Amount:     amt,
			Percentage: pct,
		})
	}
	sort.Slice(categorySlice, func(i, j int) bool {
		return categorySlice[i].Amount > categorySlice[j].Amount
	})

	if categorySlice == nil {
		categorySlice = []models.CategorySummary{}
	}

	// Determine whether the month is frozen (past month = no recalculation needed)
	now := time.Now()
	currentMonth := fmt.Sprintf("%d-%02d", now.Year(), int(now.Month()))
	isFrozen := month != currentMonth

	// Calculate budget percentage safely
	budgetPct := float64(0)
	if user.BudgetLimit > 0 {
		budgetPct = float64(totalExpenses) / float64(user.BudgetLimit) * 100
	}

	totalIncome := user.MonthlyIncome + oneTimeIncome
	available := totalIncome - totalExpenses

	summary := &models.MonthlySummary{
		ID:                bson.NewObjectID(),
		UserID:            userID,
		Month:             month,
		RecurringIncome:   user.MonthlyIncome,
		OneTimeIncome:     oneTimeIncome,
		TotalIncome:       totalIncome,
		TotalExpenses:     totalExpenses,
		Available:         available,
		BudgetLimit:       user.BudgetLimit,
		BudgetPercentage:  budgetPct,
		Savings:           maxInt64(0, available),
		ExpenseByCategory: categorySlice,
		IsFrozen:          isFrozen,
		CalculatedAt:      time.Now(),
	}

	log.Printf("Calculated summary for user %s month %s — income: ฿%d expense: ฿%d", userID, month, totalIncome, totalExpenses)
	return summary, nil
}

// GetOrCreateSummary fetches a cached summary or calculates a fresh one
func (h *SummaryHandler) GetOrCreateSummary(ctx context.Context, userID, month string) (*models.MonthlySummary, error) {
	filter := bson.M{"user_id": userID, "month": month}

	var existing models.MonthlySummary
	err := h.summariesCollection.FindOne(ctx, filter).Decode(&existing)

	if err == nil {
		// Found in DB
		if existing.IsFrozen {
			// Past month — return cached as-is
			return &existing, nil
		}
		// Current month — recalculate and update
		fresh, err := h.calculateMonthlySummary(ctx, userID, month)
		if err != nil {
			return nil, err
		}
		fresh.ID = existing.ID // preserve original document ID
		update := bson.M{"$set": fresh}
		_, _ = h.summariesCollection.UpdateOne(ctx, filter, update)
		return fresh, nil
	}

	// Not found — calculate and insert
	summary, err := h.calculateMonthlySummary(ctx, userID, month)
	if err != nil {
		return nil, err
	}
	_, err = h.summariesCollection.InsertOne(ctx, summary)
	if err != nil {
		log.Printf("Warning: could not persist summary for %s/%s: %v", userID, month, err)
	}
	return summary, nil
}

// formatMonth converts "2026-04" → "April 2026"
func formatMonth(month string) string {
	parts := strings.Split(month, "-")
	if len(parts) != 2 {
		return month
	}
	year, _ := strconv.Atoi(parts[0])
	monthNum, _ := strconv.Atoi(parts[1])
	if monthNum < 1 || monthNum > 12 {
		return month
	}
	return fmt.Sprintf("%s %d", time.Month(monthNum).String(), year)
}

// previousMonthStr returns the month string for one month before the given month
func previousMonthStr(month string) string {
	parts := strings.Split(month, "-")
	if len(parts) != 2 {
		return ""
	}
	year, _ := strconv.Atoi(parts[0])
	monthNum, _ := strconv.Atoi(parts[1])
	t := time.Date(year, time.Month(monthNum), 1, 0, 0, 0, 0, time.UTC).AddDate(0, -1, 0)
	return fmt.Sprintf("%d-%02d", t.Year(), int(t.Month()))
}

// GetMonthlySummary handles GET /api/summary/:user_id
func (h *SummaryHandler) GetMonthlySummary(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	month := c.Query("month")
	if month == "" {
		now := time.Now()
		month = fmt.Sprintf("%d-%02d", now.Year(), int(now.Month()))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Get current month summary
	summary, err := h.GetOrCreateSummary(ctx, userID, month)
	if err != nil {
		log.Printf("Error getting summary for %s/%s: %v", userID, month, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
	}

	// Get previous month summary for comparison
	prevMonth := previousMonthStr(month)
	prevSummary, err := h.GetOrCreateSummary(ctx, userID, prevMonth)
	if err != nil {
		log.Printf("Warning: could not get previous month summary: %v", err)
		prevSummary = nil
	}

	// Build savings message
	savingsMsg := ""
	if prevSummary != nil && prevSummary.Savings > 0 {
		savingsMsg = fmt.Sprintf("You saved ฿%s last month! 🐾", formatAmountCommas(prevSummary.Savings))
	}

	resp := models.MonthlySummaryResponse{
		MonthlySummary: *summary,
		FormattedMonth: formatMonth(month),
		PreviousMonth:  prevSummary,
		SavingsMessage: savingsMsg,
	}

	return c.JSON(resp)
}

// GetSummaryHistory handles GET /api/summary/:user_id/history
// Returns the last 6 months of summaries for AI Coach context
func (h *SummaryHandler) GetSummaryHistory(c *fiber.Ctx) error {
	userID := c.Params("user_id")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Build last 6 month strings (current + 5 previous)
	now := time.Now()
	var summaries []models.MonthlySummary

	for i := 0; i < 6; i++ {
		t := now.AddDate(0, -i, 0)
		month := fmt.Sprintf("%d-%02d", t.Year(), int(t.Month()))

		s, err := h.GetOrCreateSummary(ctx, userID, month)
		if err != nil {
			log.Printf("Warning: could not get summary for %s/%s: %v", userID, month, err)
			continue
		}
		summaries = append(summaries, *s)
	}

	return c.JSON(fiber.Map{
		"history": summaries,
		"count":   len(summaries),
	})
}

// formatAmountCommas formats an int64 amount with comma thousands separators
func formatAmountCommas(amount int64) string {
	s := strconv.FormatInt(amount, 10)
	n := len(s)
	if n <= 3 {
		return s
	}
	var result strings.Builder
	rem := n % 3
	if rem > 0 {
		result.WriteString(s[:rem])
	}
	for i := rem; i < n; i += 3 {
		if i > 0 || rem > 0 {
			result.WriteString(",")
		}
		result.WriteString(s[i : i+3])
	}
	return result.String()
}
// ResetSummaries handles DELETE /admin/reset-summaries
func (h *SummaryHandler) ResetSummaries(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	result, err := h.summariesCollection.DeleteMany(ctx, bson.M{})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(fiber.Map{"deleted": result.DeletedCount, "message": "All summaries reset"})
}

// DeleteAllTransactions handles DELETE /admin/reset-transactions
func (h *SummaryHandler) DeleteAllTransactions(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	userID := c.Query("user_id")
	if userID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "user_id required"})
	}
	result, err := h.transactionsCollection.DeleteMany(ctx, bson.M{"user_id": userID})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}
	return c.JSON(fiber.Map{"deleted": result.DeletedCount})
}
