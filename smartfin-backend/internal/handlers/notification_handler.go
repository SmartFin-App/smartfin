package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"github.com/google/generative-ai-go/genai"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"google.golang.org/api/option"
)

type NotificationHandler struct {
	transactionsCollection *mongo.Collection
}

func NewNotificationHandler() *NotificationHandler {
	return &NotificationHandler{
		transactionsCollection: config.GetCollection("transactions"),
	}
}

type ProcessNotificationRequest struct {
	UserID  string `json:"user_id"`
	RawText string `json:"raw_text"`
}

func (h *NotificationHandler) ProcessNotification(c *fiber.Ctx) error {
	var req ProcessNotificationRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	if req.UserID == "" || req.RawText == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id and raw_text are required"})
	}

	log.Printf("Processing notification for user: %s", req.UserID)

	ctx := context.Background()
	client, err := genai.NewClient(ctx, option.WithAPIKey(os.Getenv("GEMINI_API_KEY")))
	if err != nil {
		log.Printf("Error creating Gemini client: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create AI client"})
	}
	defer client.Close()

	model := client.GenerativeModel("gemini-2.5-flash")
	model.SetTemperature(0.1)

	prompt := fmt.Sprintf(`Analyze this bank/payment notification SMS and extract the transaction details.
Return ONLY a valid JSON object with no markdown, no code blocks, just pure JSON.

Extract:
- merchant: the store, receiver, or bank name (if Thai text, keep it or transliterate, up to you)
- amount: the total amount as an integer number only (no currency symbols, no decimals)
- type: either "income" or "expense"
- category: guess a short category like "Food", "Transfer", "Shopping", "Bills", "Groceries", "Income"
- date: the date in YYYY-MM-DD format (if not found use "%s")

Raw Notification Text:
"%s"

Example response:
{"merchant":"Starbucks","amount":150,"type":"expense","category":"Food","date":"2026-04-01"}`, time.Now().Format("2006-01-02"), req.RawText)

	resp, err := model.GenerateContent(ctx, genai.Text(prompt))
	if err != nil {
		log.Printf("Error calling Gemini: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to analyze notification"})
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "No response from AI"})
	}
	responseText := fmt.Sprintf("%v", resp.Candidates[0].Content.Parts[0])
	
	responseText = strings.TrimSpace(responseText)
	responseText = strings.TrimPrefix(responseText, "```json")
	responseText = strings.TrimPrefix(responseText, "```")
	responseText = strings.TrimSuffix(responseText, "```")
	responseText = strings.TrimSpace(responseText)

	var result struct {
		Merchant string `json:"merchant"`
		Amount   float64  `json:"amount"`
		Type     string `json:"type"`
		Category string `json:"category"`
		Date     string `json:"date"`
	}

	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		log.Printf("Error parsing Gemini JSON response: %v", err)
		log.Printf("Raw response: %s", responseText)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to parse AI output"})
	}

	dateParsed, err := time.Parse("2006-01-02", result.Date)
	if err != nil {
		dateParsed = time.Now()
	}

	transaction := models.Transaction{
		ID:        bson.NewObjectID(),
		UserID:    req.UserID,
		Merchant:  result.Merchant,
		Amount:    int64(result.Amount),
		Type:      result.Type,
		Category:  result.Category,
		Source:    "notification",
		Date:      dateParsed,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	_, err = h.transactionsCollection.InsertOne(ctx, transaction)
	if err != nil {
		log.Printf("Error saving transaction: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to save transaction"})
	}
	
	// Update summary
	summaryHandler := NewSummaryHandler()
	monthStr := fmt.Sprintf("%d-%02d", dateParsed.Year(), int(dateParsed.Month()))
	go func() {
		// Use a detached context for the async background job
		bgCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_, _ = summaryHandler.GetOrCreateSummary(bgCtx, req.UserID, monthStr)
	}()

	return c.JSON(fiber.Map{
		"message": "Transaction created from notification",
		"transaction": transaction,
	})
}
