package handlers

import (
	"context"
	"fmt"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

type TransactionHandler struct {
	collection *mongo.Collection
}

func NewTransactionHandler() *TransactionHandler {
	return &TransactionHandler{
		collection: config.GetCollection("transactions"),
	}
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

	if req.UserID == "" || req.Merchant == "" || req.Amount == 0 || req.Type == "" || req.Category == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id, merchant, amount, type, and category must not be empty"})
	}

	if req.Type != "expense" && req.Type != "income" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Type must be 'expense' or 'income'"})
	}

	if req.Amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Amount must be greater than 0"})
	}

	var txDate time.Time
	if req.Date != "" {
		formats := []string{
			"2006-01-02",
			time.RFC3339,
			"2006-01-02T15:04:05Z07:00",
		}
		var err error
		for _, format := range formats {
			txDate, err = time.Parse(format, req.Date)
			if err == nil {
				break
			}
		}
		if err != nil {
			txDate = time.Now()
		}
	} else {
		txDate = time.Now()
	}

	source := req.Source
	if source == "" {
		source = "manual"
	}

	now := time.Now()
	tx := models.Transaction{
		ID:       bson.NewObjectID(),
		UserID:   req.UserID,
		Merchant: req.Merchant,
		Amount:   req.Amount,
		Type:     req.Type,
		Category: req.Category,
		Source:   source,
		Date:     txDate,
		CreatedAt: now,
		UpdatedAt: now,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err := h.collection.InsertOne(ctx, tx)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create transaction"})
	}

	return c.Status(fiber.StatusCreated).JSON(tx)
}

// 2. GetTransactions
func (h *TransactionHandler) GetTransactions(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	tType := c.Query("type")
	category := c.Query("category")
	limit := c.QueryInt("limit", 50)
	skip := c.QueryInt("skip", 0)

	filter := bson.M{"user_id": userID}
	if tType != "" {
		filter["type"] = tType
	}
	if category != "" {
		filter["category"] = category
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
	err = h.collection.FindOne(ctx, bson.M{"_id": objID}).Decode(&tx)
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

	updateData := bson.M{}
	if req.Merchant != nil {
		updateData["merchant"] = *req.Merchant
	}
	if req.Amount != nil {
		updateData["amount"] = *req.Amount
	}
	if req.Type != nil {
		updateData["type"] = *req.Type
	}
	if req.Category != nil {
		updateData["category"] = *req.Category
	}
	if req.Source != nil {
		updateData["source"] = *req.Source
	}
	if req.Date != nil {
		formats := []string{
			"2006-01-02",
			time.RFC3339,
			"2006-01-02T15:04:05Z07:00",
		}
		var parsedDate time.Time
		var err error
		for _, format := range formats {
			parsedDate, err = time.Parse(format, *req.Date)
			if err == nil {
				updateData["date"] = parsedDate
				break
			}
		}
	}

	if len(updateData) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No update fields provided"})
	}

	updateData["updated_at"] = time.Now()
	update := bson.M{"$set": updateData}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	res, err := h.collection.UpdateOne(ctx, bson.M{"_id": objID}, update)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update transaction"})
	}

	if res.MatchedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

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

	res, err := h.collection.DeleteOne(ctx, bson.M{"_id": objID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to delete transaction"})
	}

	if res.DeletedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Transaction not found"})
	}

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

	var income, expense int64
	cats := make([]map[string]interface{}, 0)

	if len(results) > 0 {
		for _, t := range results[0].Totals {
			if t.ID == "income" {
				income = t.Total
			} else if t.ID == "expense" {
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
		"total_income":        income,
		"total_expenses":      expense,
		"available_to_spend":  income - expense,
		"expense_by_category": cats,
	})
}
