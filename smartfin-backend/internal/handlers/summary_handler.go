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
	"go.mongodb.org/mongo-driver/v2/mongo/options"

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

	// Parse "2026-04" into its [start, end) window
	startDate, endDate, err := summaries.Bounds(month)
	if err != nil {
		return nil, err
	}

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

	// A month is frozen only once it has fully elapsed. Deriving this from the
	// window (rather than comparing month strings against the server's clock)
	// keeps a client an hour ahead of the server from freezing a live month at zero.
	isFrozen := !time.Now().Before(endDate)

	// Calculate budget percentage safely
	budgetPct := float64(0)
	if user.BudgetLimit > 0 {
		budgetPct = float64(totalExpenses) / float64(user.BudgetLimit) * 100
	}

	// Recurring income is an assumption taken from the profile, not a recorded
	// transaction. Carrying it into a month that has already ended and holds no
	// activity at all invents a salary out of nothing — and with no expenses to
	// offset it, a brand-new user was congratulated for "saving" a full month's
	// income in a month before they had even signed up.
	//
	// The test is "elapsed and empty", not "before signup": a past month that
	// does contain transactions is evidence the user was active, so the standing
	// income still applies. The current month always keeps it, since that figure
	// is what the dashboard budgets against from day one.
	recurringIncome := user.MonthlyIncome
	if isFrozen && len(transactions) == 0 {
		recurringIncome = 0
	}

	totalIncome := recurringIncome + oneTimeIncome
	available := totalIncome - totalExpenses

	summary := &models.MonthlySummary{
		ID:                bson.NewObjectID(),
		UserID:            userID,
		Month:             month,
		RecurringIncome:   recurringIncome,
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

// maxSavingsMonths bounds the walk-back. Each month costs a summary lookup, and a
// goal that counts more than two years of history stops meaning much anyway.
const maxSavingsMonths = 24

// GetSavingsProgress handles GET /api/summary/:user_id/savings-goal
//
// "Saved so far" is the sum of each COMPLETED month's savings (income minus
// expenses, floored at zero) since the account was created. It is derived rather
// than tracked separately, so there is no balance for the user to keep up to date
// and no second source of truth to drift from the transactions.
//
// The current month is deliberately excluded and reported separately as
// this_month_surplus. A month's income lands in the summary on day one, so folding
// the live month in meant a ฿12,000 salary counted as ฿12,000 "saved" before any
// of it had been lived through — a ฿5,000 goal read as reached on the 1st, then
// un-reached as the user spent. Surplus only becomes savings once the month ends.
func (h *SummaryHandler) GetSavingsProgress(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var user models.User
	if err := h.usersCollection.FindOne(ctx, bson.M{"firebase_uid": userID}).Decode(&user); err != nil {
		if err == mongo.ErrNoDocuments {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch user"})
	}

	now := time.Now().In(summaries.Zone)
	anchor := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, summaries.Zone)

	// Count from whichever came first: the account being created, or the oldest
	// transaction on record. Bounding on signup alone hid every backdated entry —
	// a user who scans older slips (or a seeded demo account) has history that
	// legitimately predates the profile document.
	startAnchor := anchor
	if !user.CreatedAt.IsZero() {
		created := user.CreatedAt.In(summaries.Zone)
		startAnchor = time.Date(created.Year(), created.Month(), 1, 0, 0, 0, 0, summaries.Zone)
	}

	var oldest models.Transaction
	oldestOpts := options.FindOne().SetSort(bson.D{{Key: "date", Value: 1}})
	if err := h.transactionsCollection.FindOne(ctx, bson.M{"user_id": userID}, oldestOpts).Decode(&oldest); err == nil {
		t := oldest.Date.In(summaries.Zone)
		txAnchor := time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, summaries.Zone)
		if txAnchor.Before(startAnchor) {
			startAnchor = txAnchor
		}
	}

	months := (anchor.Year()-startAnchor.Year())*12 + int(anchor.Month()) - int(startAnchor.Month()) + 1
	if months > maxSavingsMonths {
		months = maxSavingsMonths
	}
	if months < 1 {
		months = 1
	}

	var saved int64
	var lastMonthSavings int64
	var thisMonthSurplus int64
	counted := 0

	for i := 0; i < months; i++ {
		month := summaries.StringOf(anchor.AddDate(0, -i, 0))
		s, err := h.GetOrCreateSummary(ctx, userID, month)
		if err != nil {
			log.Printf("Warning: savings progress skipped %s/%s: %v", userID, month, err)
			continue
		}

		if i == 0 {
			// In progress: shown as context, never counted toward the goal.
			thisMonthSurplus = s.Savings
			continue
		}

		saved += s.Savings
		if i == 1 {
			lastMonthSavings = s.Savings
		}
		counted++
	}

	goal := user.SavingsGoal
	percentage := float64(0)
	var remaining int64
	if goal > 0 {
		remaining = maxInt64(0, goal-saved)
		percentage = float64(saved) / float64(goal) * 100
		if percentage > 100 {
			percentage = 100
		}
	}

	return c.JSON(fiber.Map{
		"user_id":            userID,
		"has_goal":           goal > 0,
		"goal":               goal,
		"goal_name":          user.SavingsGoalName,
		"target_date":        user.SavingsTargetDate,
		"saved":              saved,
		"remaining":          remaining,
		"percentage":         percentage,
		"last_month_savings": lastMonthSavings,
		"this_month_surplus": thisMonthSurplus,
		// Completed months only — the in-progress one is not among them.
		"months_counted": counted,
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
