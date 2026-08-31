package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"

	"github.com/SmartFin-App/smartfin-backend/internal/agents"
)

// CoachHandler handles AI coach requests, acting as the main Gemini Agent
type CoachHandler struct {
	retrievalAgent *agents.RetrievalAgent
	actionAgent    *agents.ActionAgent
}

// NewCoachHandler creates a new CoachHandler
func NewCoachHandler() *CoachHandler {
	return &CoachHandler{
		retrievalAgent: agents.NewRetrievalAgent(),
		actionAgent:    agents.NewActionAgent(),
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

	// 1. Retrieval Agent fetches personal context
	userContext := h.retrievalAgent.GetUserContext(ctx, req.UserID)
	transactionContext := h.retrievalAgent.GetTransactionContext(ctx, req.UserID)
	summaryContext := h.retrievalAgent.GetSummaryContext(ctx, req.UserID)

	systemPrompt := fmt.Sprintf(`You are SmartFin Coach, a friendly and knowledgeable AI financial advisor for a Thai user.
You speak in a warm, encouraging tone. You use the paw print emoji 🐾 occasionally.
You have access to the user's financial data, tools to modify their budget/goals/transactions, and Google Search for external research.

%s

%s

%s

Answer the user's question. Use the provided tools if the user wants to update their budget, set a savings goal, or add a transaction. Use Google Search if they ask a general market question (like interest rates, stock trends).
Keep responses concise — maximum 3-4 sentences unless the user asks for detail.
Format amounts in Thai Baht (฿) with no decimals.`,
		userContext, transactionContext, summaryContext)

	// Create Gemini client
	geminiClient, err := genai.NewClient(ctx, option.WithAPIKey(os.Getenv("GEMINI_API_KEY")))
	if err != nil {
		log.Printf("Error creating Gemini client for coach: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create AI client"})
	}
	defer geminiClient.Close()

	model := geminiClient.GenerativeModel("gemini-2.5-flash")
	model.SetTemperature(0.7)
	model.SystemInstruction = genai.NewUserContent(genai.Text(systemPrompt))

	// Define Action Agent tools
	actionTools := &genai.Tool{
		FunctionDeclarations: []*genai.FunctionDeclaration{
			{
				Name:        "set_savings_goal",
				Description: "Sets a savings goal for the user.",
				Parameters: &genai.Schema{
					Type: genai.TypeObject,
					Properties: map[string]*genai.Schema{
						"goal_amount": {Type: genai.TypeNumber, Description: "The savings goal amount in THB"},
					},
					Required: []string{"goal_amount"},
				},
			},
			{
				Name:        "update_budget_limit",
				Description: "Updates the monthly budget limit for the user.",
				Parameters: &genai.Schema{
					Type: genai.TypeObject,
					Properties: map[string]*genai.Schema{
						"budget_limit": {Type: genai.TypeNumber, Description: "The new monthly budget limit in THB"},
					},
					Required: []string{"budget_limit"},
				},
			},
			{
				Name:        "add_transaction",
				Description: "Adds a new manual transaction (income or expense) for the user.",
				Parameters: &genai.Schema{
					Type: genai.TypeObject,
					Properties: map[string]*genai.Schema{
						"merchant": {Type: genai.TypeString, Description: "The name of the merchant, person, or bank"},
						"amount":   {Type: genai.TypeNumber, Description: "The transaction amount in THB"},
						"type":     {Type: genai.TypeString, Description: "Either 'income' or 'expense'"},
						"category": {Type: genai.TypeString, Description: "Category like 'Food', 'Transport', 'Shopping', 'Salary', etc."},
					},
					Required: []string{"merchant", "amount", "type", "category"},
				},
			},
		},
	}

	// Add tools (Action Agent functions)
	model.Tools = []*genai.Tool{
		actionTools,
	}

	// Setup chat history
	chat := model.StartChat()
	for _, hist := range req.History {
		role := hist.Role
		if role == "user" || role == "model" {
			chat.History = append(chat.History, &genai.Content{
				Role:  role,
				Parts: []genai.Part{genai.Text(hist.Content)},
			})
		}
	}

	// Send message
	resp, err := chat.SendMessage(ctx, genai.Text(req.Message))
	if err != nil {
		log.Printf("Error sending message to Gemini: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to get AI response"})
	}

	// Handle function calls
	for len(resp.Candidates) > 0 && len(resp.Candidates[0].Content.Parts) > 0 {
		part := resp.Candidates[0].Content.Parts[0]
		funcCall, ok := part.(genai.FunctionCall)
		if !ok {
			break // It's a text response, break out of loop
		}

		log.Printf("AI requested function call: %s", funcCall.Name)
		var result string

		switch funcCall.Name {
		case "set_savings_goal":
			if amount, ok := funcCall.Args["goal_amount"].(float64); ok {
				result = h.actionAgent.SetSavingsGoal(ctx, req.UserID, amount)
			}
		case "update_budget_limit":
			if limit, ok := funcCall.Args["budget_limit"].(float64); ok {
				result = h.actionAgent.UpdateBudgetLimit(ctx, req.UserID, limit)
			}
		case "add_transaction":
			merchant, _ := funcCall.Args["merchant"].(string)
			amount, _ := funcCall.Args["amount"].(float64)
			txType, _ := funcCall.Args["type"].(string)
			category, _ := funcCall.Args["category"].(string)
			result = h.actionAgent.AddTransaction(ctx, req.UserID, merchant, amount, txType, category)
		default:
			result = "Function not implemented."
		}

		// Send function result back to the model
		resultJSON, _ := json.Marshal(map[string]string{"result": result})
		resp, err = chat.SendMessage(ctx, genai.FunctionResponse{
			Name: funcCall.Name,
			Response: map[string]any{
				"result": string(resultJSON),
			},
		})
		if err != nil {
			log.Printf("Error sending function response to Gemini: %v", err)
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to get AI response after action"})
		}
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "No response from AI"})
	}

	responseText := fmt.Sprintf("%v", resp.Candidates[0].Content.Parts[0])
	
	// Handle edge case where function response is nil/empty but text is present
	if len(resp.Candidates[0].Content.Parts) > 1 {
	    // Sometimes Gemini returns function call + text in same response
	    for _, p := range resp.Candidates[0].Content.Parts {
	        if t, ok := p.(genai.Text); ok {
	            responseText = string(t)
	        }
	    }
	}
	
	log.Printf("Coach response for user %s: %d chars", req.UserID, len(responseText))

	return c.JSON(fiber.Map{
		"response": responseText,
		"user_id":  req.UserID,
	})
}
