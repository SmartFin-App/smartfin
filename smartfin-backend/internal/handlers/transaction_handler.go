package handlers

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type TransactionHandler struct {
	collection          *mongo.Collection
	summariesCollection *mongo.Collection
}

func NewTransactionHandler() *TransactionHandler {
	return &TransactionHandler{
		collection:          config.GetCollection("transactions"),
		summariesCollection: config.GetCollection("monthly_summaries"),
	}
}

// ownerFromRequest resolves the acting user's Firebase UID from the query string or
// request body. Firebase tokens are not verified yet, so this is an ownership scope
// rather than authentication — but it stops a guessed ObjectID from reaching another
// user's record, and it is the single place to swap for a verified token later.
func ownerFromRequest(c *fiber.Ctx) string {
	if uid := strings.TrimSpace(c.Query("user_id")); uid != "" {
		return uid
	}
	var body struct {
		UserID string `json:"user_id"`
	}
	if err := c.BodyParser(&body); err == nil {
		return strings.TrimSpace(body.UserID)
	}
	return ""
}

// parseTxDate parses the date formats the clients send. It returns ok=false rather
// than defaulting to today, so a date the server cannot read is reported instead of
// silently filing the transaction under the wrong month.
func parseTxDate(raw string) (time.Time, bool) {
	formats := []string{
		"2006-01-02",
		time.RFC3339,
		"2006-01-02T15:04:05Z07:00",
	}
	for _, format := range formats {
		if parsed, err := time.Parse(format, raw); err == nil {
			return parsed, true
		}
	}
	return time.Time{}, false
}

// Helpers for string formatting
func addCommas(s string) string {
	var res []byte
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			res = append(res, ',')
		}
		res = append(res, byte(c))
	}
	return string(res)
}

func formatAmount(amount int64, tType string) string {
	formatted := fmt.Sprintf("%d", amount)
	withCommas := addCommas(formatted)
	if tType == "income" {
		return "+฿" + withCommas
	}
	return "-฿" + withCommas
}

func formatDate(d time.Time) string {
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	txDate := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, d.Location())

	if txDate.Equal(today) {
		return "Today"
	} else if txDate.Equal(today.AddDate(0, 0, -1)) {
		return "Yesterday"
	}
	return d.Format("Jan 02")
}

// 1. CreateTransaction
func (h *TransactionHandler) CreateTransaction(c *fiber.Ctx) error {
	var req struct {
		UserID   string `json:"user_id"`
		Merchant string `json:"merchant"`
		Amount   int64  `json:"amount"`
		Type     string `json:"type"`
		Category string `json:"category"`
		Source   string `json:"source"`
		Date     string `json:"date"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	// SmartFin records expenses only. An omitted type means expense; anything
	// else is refused rather than stored somewhere the app can no longer show it.
	if req.Type == "" {
		req.Type = "expense"
	}
	if req.UserID == "" || req.Merchant == "" || req.Amount == 0 || req.Category == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id, merchant, amount, and category must not be empty"})
	}

	if req.Type != "expense" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "SmartFin records expenses only"})
	}

	if req.Amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Amount must be greater than 0"})
	}

	txDate := time.Now()
	if req.Date != "" {
		parsed, ok := parseTxDate(req.Date)
		if !ok {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid date format, expected YYYY-MM-DD"})
		}
		txDate = parsed
	}

	source := req.Source
	if source == "" {
		source = "manual"
	}

	now := time.Now()
	tx := models.Transaction{
		ID:        bson.NewObjectID(),
		UserID:    req.UserID,
		Merchant:  req.Merchant,
		Amount:    req.Amount,
		Type:      req.Type,
		Category:  req.Category,
		Source:    source,
		Date:      txDate,
		CreatedAt: now,
		UpdatedAt: now,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err := h.collection.InsertOne(ctx, tx)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create transaction"})
	}

	summaries.InvalidateFor(ctx, h.summariesCollection, tx.UserID, tx.Date)

	return c.Status(fiber.StatusCreated).JSON(tx)
}

// 2. GetTransactions
func (h *TransactionHandler) GetTransactions(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	category := c.Query("category")
	month := c.Query("month")
	search := c.Query("search")
	limit := c.QueryInt("limit", 50)
	skip := c.QueryInt("skip", 0)

	// Expenses only. Income rows can still exist from before SmartFin became
	// spending-only; they stay in the database but never appear.
	filter := bson.M{"user_id": userID, "type": "expense"}
	if category != "" {
		filter["category"] = category
	}
	if month != "" {
		// Same +07:00 window the summaries use, so a filtered list and the month
		// summary can never disagree about which transactions belong to a month.
		start, end, err := summaries.Bounds(month)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
		}
		filter["date"] = bson.M{"$gte": start, "$lt": end}
	}
	if search != "" {
		// Anchored nowhere and case-insensitive: users search for a fragment of a
		// merchant name, not its exact prefix.
		filter["merchant"] = bson.M{"$regex": regexp.QuoteMeta(search), "$options": "i"}
	}

	opts := options.Find().
		SetSort(bson.D{{Key: "date", Value: -1}}).
		SetLimit(int64(limit)).
		SetSkip(int64(skip))

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cursor, err := h.collection.Find(ctx, filter, opts)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch transactions"})
	}
	defer cursor.Close(ctx)

	var transactions []models.Transaction
	if err = cursor.All(ctx, &transactions); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Error parsing transactions"})
	}

	responses := make([]models.TransactionResponse, 0, len(transactions))
	for _, tx := range transactions {
		responses = append(responses, models.TransactionResponse{
			Transaction:     tx,
			FormattedAmount: formatAmount(tx.Amount, tx.Type),
			FormattedDate:   formatDate(tx.Date),
		})
	}

	return c.Status(fiber.StatusOK).JSON(responses)
}

// 3. GetTransactionByID
func (h *TransactionHandler) GetTransactionByID(c *fiber.Ctx) error {
	idParam := c.Params("id")
	objID, err := bson.ObjectIDFromHex(idParam)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid transaction ID format"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var tx models.Transaction
	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	err = h.collection.FindOne(ctx, bson.M{"_id": objID, "user_id": userID}).Decode(&tx)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch transaction"})
	}

	return c.Status(fiber.StatusOK).JSON(tx)
}

// 4. UpdateTransaction
func (h *TransactionHandler) UpdateTransaction(c *fiber.Ctx) error {
	idParam := c.Params("id")
	objID, err := bson.ObjectIDFromHex(idParam)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid transaction ID format"})
	}

	var req models.UpdateTransactionRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Scope the write to its owner. Without this the handler has no notion of an
	// owner at all, so a guessed ObjectID rewrites another user's record.
	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	var existing models.Transaction
	if err := h.collection.FindOne(ctx, bson.M{"_id": objID, "user_id": userID}).Decode(&existing); err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

	// The same guards CreateTransaction applies — without them an update writes a
	// negative amount or an out-of-enum type that every summary then miscounts.
	if req.Amount != nil && *req.Amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Amount must be greater than 0"})
	}
	if req.Type != nil && *req.Type != "expense" && *req.Type != "income" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Type must be 'expense' or 'income'"})
	}

	updateData := bson.M{}
	if req.Merchant != nil {
		updateData["merchant"] = *req.Merchant
	}
	if req.Amount != nil {
		updateData["amount"] = *req.Amount
	}
	if req.Type != nil && *req.Type != "expense" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "SmartFin records expenses only"})
	}
	if req.Category != nil {
		updateData["category"] = *req.Category
	}
	if req.Source != nil {
		updateData["source"] = *req.Source
	}
	if req.Date != nil {
		parsed, ok := parseTxDate(*req.Date)
		if !ok {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid date format, expected YYYY-MM-DD"})
		}
		updateData["date"] = parsed
	}

	if len(updateData) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No update fields provided"})
	}

	updateData["updated_at"] = time.Now()
	update := bson.M{"$set": updateData}

	res, err := h.collection.UpdateOne(ctx, bson.M{"_id": objID, "user_id": userID}, update)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update transaction"})
	}

	if res.MatchedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

	// An edit that moves a transaction across a month boundary makes both stale.
	newDate := existing.Date
	if d, ok := updateData["date"].(time.Time); ok {
		newDate = d
	}
	summaries.InvalidateFor(ctx, h.summariesCollection, userID, existing.Date, newDate)

	return c.Status(fiber.StatusOK).JSON(fiber.Map{"message": "Transaction updated successfully"})
}

// 5. DeleteTransaction
func (h *TransactionHandler) DeleteTransaction(c *fiber.Ctx) error {
	idParam := c.Params("id")
	objID, err := bson.ObjectIDFromHex(idParam)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid transaction ID format"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	var existing models.Transaction
	if err := h.collection.FindOne(ctx, bson.M{"_id": objID, "user_id": userID}).Decode(&existing); err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

	res, err := h.collection.DeleteOne(ctx, bson.M{"_id": objID, "user_id": userID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to delete transaction"})
	}

	if res.DeletedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

	summaries.InvalidateFor(ctx, h.summariesCollection, userID, existing.Date)

	return c.Status(fiber.StatusOK).JSON(fiber.Map{"message": "Transaction deleted successfully"})
}

// 6. GetTransactionSummary
func (h *TransactionHandler) GetTransactionSummary(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	monthStr := c.Query("month")
	var startOfMonth time.Time
	if monthStr == "" {
		now := time.Now()
		startOfMonth = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	} else {
		parsed, err := time.Parse("2006-01", monthStr)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid month format. Use YYYY-MM"})
		}
		startOfMonth = parsed
	}

	nextMonth := startOfMonth.AddDate(0, 1, 0)

	matchStage := bson.D{{Key: "$match", Value: bson.D{
		{Key: "user_id", Value: userID},
		{Key: "date", Value: bson.D{
			{Key: "$gte", Value: startOfMonth},
			{Key: "$lt", Value: nextMonth},
		}},
	}}}

	facetStage := bson.D{{Key: "$facet", Value: bson.D{
		{Key: "totals", Value: bson.A{
			bson.D{{Key: "$group", Value: bson.D{
				{Key: "_id", Value: "$type"},
				{Key: "total", Value: bson.D{{Key: "$sum", Value: "$amount"}}},
			}}},
		}},
		{Key: "categories", Value: bson.A{
			bson.D{{Key: "$match", Value: bson.D{{Key: "type", Value: "expense"}}}},
			bson.D{{Key: "$group", Value: bson.D{
				{Key: "_id", Value: "$category"},
				{Key: "total", Value: bson.D{{Key: "$sum", Value: "$amount"}}},
			}}},
			bson.D{{Key: "$sort", Value: bson.D{{Key: "total", Value: -1}}}},
		}},
	}}}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cursor, err := h.collection.Aggregate(ctx, mongo.Pipeline{matchStage, facetStage})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to calculate summary"})
	}
	defer cursor.Close(ctx)

	type SummaryResult struct {
		Totals []struct {
			ID    string `bson:"_id"`
			Total int64  `bson:"total"`
		} `bson:"totals"`
		Categories []struct {
			ID    string `bson:"_id"`
			Total int64  `bson:"total"`
		} `bson:"categories"`
	}

	var results []SummaryResult
	if err = cursor.All(ctx, &results); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to parse summary"})
	}

	var expense int64
	cats := make([]map[string]interface{}, 0)

	if len(results) > 0 {
		for _, t := range results[0].Totals {
			if t.ID == "expense" {
				expense = t.Total
			}
		}
		for _, c := range results[0].Categories {
			cats = append(cats, map[string]interface{}{
				"category": c.ID,
				"total":    c.Total,
			})
		}
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"total_expenses":      expense,
		"expense_by_category": cats,
	})
}
