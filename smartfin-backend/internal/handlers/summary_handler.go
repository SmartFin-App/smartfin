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
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
)

// SummaryHandler handles monthly financial summary requests
type SummaryHandler struct {
	summariesCollection    *mongo.Collection
	transactionsCollection *mongo.Collection
	usersCollection        *mongo.Collection
}

// NewSummaryHandler creates a new SummaryHandler
func NewSummaryHandler() *SummaryHandler {
	return &SummaryHandler{
		summariesCollection:    config.GetCollection("monthly_summaries"),
		transactionsCollection: config.GetCollection("transactions"),
		usersCollection:        config.GetCollection("users"),
	}
}

// calculateMonthlySummary computes a fresh MonthlySummary from transactions
func (h *SummaryHandler) calculateMonthlySummary(ctx context.Context, userID, month string) (*models.MonthlySummary, error) {
	var user models.User
	if err := h.usersCollection.FindOne(ctx, bson.M{"firebase_uid": userID}).Decode(&user); err != nil {
		if err == mongo.ErrNoDocuments {
			// New user without a profile yet: no budget to measure against.
			user = models.User{FirebaseUID: userID}
		} else {
			return nil, fmt.Errorf("database error: %w", err)
		}
	}

	// Parse "2026-04" into its [start, end) window
	startDate, endDate, err := summaries.Bounds(month)
	if err != nil {
		return nil, err
	}

	// Expenses only. Income transactions may still exist in the database from
	// before SmartFin became spending-only; they no longer count toward anything.
	filter := bson.M{
		"user_id": userID,
		"type":    "expense",
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

	// Expense total and category breakdown
	var totalExpenses int64
	categoryMap := make(map[string]int64)

	for _, t := range transactions {
		totalExpenses += t.Amount
		categoryMap[t.Category] += t.Amount
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

	// A month is frozen only once it has fully elapsed. Deriving this from the
	// window (rather than comparing month strings against the server's clock)
	// keeps a client an hour ahead of the server from freezing a live month at zero.
	isFrozen := !time.Now().Before(endDate)

	// Calculate budget percentage safely
	budgetPct := float64(0)
	if user.BudgetLimit > 0 {
		budgetPct = float64(totalExpenses) / float64(user.BudgetLimit) * 100
	}

	summary := &models.MonthlySummary{
		ID:                bson.NewObjectID(),
		UserID:            userID,
		Month:             month,
		TotalExpenses:     totalExpenses,
		BudgetLimit:       user.BudgetLimit,
		BudgetPercentage:  budgetPct,
		ExpenseByCategory: categorySlice,
		IsFrozen:          isFrozen,
		CalculatedAt:      time.Now(),
	}

	log.Printf("Calculated summary for user %s month %s — expense: ฿%d", userID, month, totalExpenses)
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
		// ReplaceOne, not $set: a $set document carrying _id is rejected as an
		// immutable-field update, which silently left the cached copy stale while
		// the caller still saw correct in-memory numbers.
		fresh.ID = existing.ID // preserve original document ID
		if _, err := h.summariesCollection.ReplaceOne(ctx, bson.M{"_id": existing.ID}, fresh); err != nil {
			log.Printf("Warning: could not refresh summary for %s/%s: %v", userID, month, err)
		}
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

	resp := models.MonthlySummaryResponse{
		MonthlySummary: *summary,
		FormattedMonth: formatMonth(month),
		PreviousMonth:  prevSummary,
	}

	return c.JSON(resp)
}

// GetSummaryHistory handles GET /api/summary/:user_id/history
// Returns the last 6 months of summaries for AI Coach context
func (h *SummaryHandler) GetSummaryHistory(c *fiber.Ctx) error {
	userID := c.Params("user_id")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Build last 6 month strings (current + 5 previous). Anchor to the first of
	// the month before subtracting: AddDate normalises overflow days, so running
	// this on the 31st would otherwise skip 30-day months and duplicate others.
	now := time.Now().In(summaries.Zone)
	anchor := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, summaries.Zone)
	var history []models.MonthlySummary

	for i := 0; i < 6; i++ {
		month := summaries.StringOf(anchor.AddDate(0, -i, 0))

		s, err := h.GetOrCreateSummary(ctx, userID, month)
		if err != nil {
			log.Printf("Warning: could not get summary for %s/%s: %v", userID, month, err)
			continue
		}
		history = append(history, *s)
	}

	return c.JSON(fiber.Map{
		"history": history,
		"count":   len(history),
	})
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
