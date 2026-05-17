package handlers

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/generative-ai-go/genai"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"google.golang.org/api/option"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
)

// CoachHandler handles AI coach requests
type CoachHandler struct {
	transactionsCollection *mongo.Collection
	usersCollection        *mongo.Collection
}

// NewCoachHandler creates a new CoachHandler
func NewCoachHandler() *CoachHandler {
	return &CoachHandler{
		transactionsCollection: config.GetCollection("transactions"),
		usersCollection:        config.GetCollection("users"),
	}
}

// AskCoachRequest is the request body for the AskCoach endpoint
type AskCoachRequest struct {
	UserID  string `json:"user_id"`
	Message string `json:"message"`
	History []struct {
		Role    string `json:"role"`    // "user" or "model"
		Content string `json:"content"`
	} `json:"history"`
}

// AskCoach handles POST /api/coach/ask
func (h *CoachHandler) AskCoach(c *fiber.Ctx) error {
	var req AskCoachRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}
	if req.UserID == "" || req.Message == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id and message are required"})
	}

	log.Printf("Coach question from user %s: %s", req.UserID, req.Message)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Fetch user profile
	var user models.User
	err := h.usersCollection.FindOne(ctx, bson.M{"firebase_uid": req.UserID}).Decode(&user)
	if err != nil {
		log.Printf("User not found for coach: %v", err)
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
	}

	// Fetch last 50 transactions sorted by date descending
	opts := options.Find().SetSort(bson.D{{Key: "date", Value: -1}}).SetLimit(50)
	cursor, err := h.transactionsCollection.Find(ctx, bson.M{"user_id": req.UserID}, opts)
	if err != nil {
		log.Printf("Error fetching transactions for coach: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch transactions"})
	}
	defer cursor.Close(ctx)

	var transactions []models.Transaction
	if err := cursor.All(ctx, &transactions); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to decode transactions"})
	}

	// Build transaction context string
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

	// Fetch 6-month summary history for trend analysis
	summaryHandler := NewSummaryHandler()
	var summaryContext strings.Builder
	summaryContext.WriteString("\nMonthly Summary History (last 6 months):\n")

	now := time.Now()
	for i := 0; i < 6; i++ {
		targetDate := now.AddDate(0, -i, 0)
		month := fmt.Sprintf("%d-%02d", targetDate.Year(), targetDate.Month())
		summary, err := summaryHandler.GetOrCreateSummary(ctx, req.UserID, month)
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

	// Build user context string
	userContext := fmt.Sprintf(`User Profile:
- Name: %s
- Monthly Income: ฿%d
- Income Bracket: %s
- Current Status: %s
- Financial Health Goal: %s
- Budget Limit: ฿%d`,
		user.Name, user.MonthlyIncome, user.IncomeBracket,
		user.CurrentStatus, user.FinancialHealth, user.BudgetLimit,
	)

	// Build the full RAG system prompt
	systemPrompt := fmt.Sprintf(`You are SmartFin Coach, a friendly and knowledgeable AI financial advisor for a Thai user.
You speak in a warm, encouraging tone. You use the paw print emoji 🐾 occasionally.
You always give specific, actionable advice based on the user's actual data.
You format amounts in Thai Baht (฿) with no decimals.
Keep responses concise — maximum 3-4 sentences unless the user asks for detail.
When you spot spending trends across months, mention them proactively.

%s

%s

%s

Answer the user's question based on their actual financial data above.
If you see trends across months, mention them.
If you need to calculate something, show the calculation briefly.
If the user asks something unrelated to finance, gently redirect them.`,
		userContext,
		transactionContext.String(),
		summaryContext.String(),
	)

	// Create Gemini client
	geminiClient, err := genai.NewClient(ctx, option.WithAPIKey(os.Getenv("GEMINI_API_KEY")))
	if err != nil {
		log.Printf("Error creating Gemini client for coach: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create AI client"})
	}
	defer geminiClient.Close()

	model := geminiClient.GenerativeModel("gemini-2.5-flash")
	model.SetTemperature(0.7)
	model.SystemInstruction = &genai.Content{
		Parts: []genai.Part{genai.Text(systemPrompt)},
	}

	// Use chat session with conversation history
	chat := model.StartChat()
	for _, h := range req.History {
		role := h.Role
		if role == "user" || role == "model" {
			chat.History = append(chat.History, &genai.Content{
				Role:  role,
				Parts: []genai.Part{genai.Text(h.Content)},
			})
		}
	}

	resp, err := chat.SendMessage(ctx, genai.Text(req.Message))
	if err != nil {
		log.Printf("Error sending message to Gemini: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to get AI response"})
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "No response from AI"})
	}

	responseText := fmt.Sprintf("%v", resp.Candidates[0].Content.Parts[0])
	log.Printf("Coach response for user %s: %d chars", req.UserID, len(responseText))

	return c.JSON(fiber.Map{
		"response": responseText,
		"user_id":  req.UserID,
	})
}
