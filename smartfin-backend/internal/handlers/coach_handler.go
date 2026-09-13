package handlers

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/agents"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// CoachHandler handles AI coach requests via the Gemini Agent Orchestrator
type CoachHandler struct {
	orchestrator    *agents.Orchestrator
	chatMessagesCol *mongo.Collection
}

// NewCoachHandler creates a new CoachHandler
func NewCoachHandler() *CoachHandler {
	return &CoachHandler{
		orchestrator:    agents.NewOrchestrator(),
		chatMessagesCol: config.GetCollection("chat_messages"),
	}
}

// AskCoachRequest is the request body for the AskCoach endpoint
type AskCoachRequest struct {
	UserID  string `json:"user_id"`
	Message string `json:"message"`
	History []struct {
		Role    string `json:"role"` // "user" or "model"
		Content string `json:"content"`
	} `json:"history"`
	// Debug asks for the tool trace. It is honoured only when the server runs with
	// COACH_EVAL_TRACE=1, so a client cannot make a normal deployment return raw
	// tool results.
	Debug bool `json:"debug"`
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

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	debug := req.Debug && os.Getenv("COACH_EVAL_TRACE") == "1"

	output, err := h.orchestrator.ProcessQuery(ctx, agents.AskCoachInput{
		UserID:  req.UserID,
		Message: req.Message,
		History: req.History,
		Debug:   debug,
	})
	if err != nil {
		log.Printf("Coach orchestrator error for user %s: %v", req.UserID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error":   "Failed to get AI response",
			"details": err.Error(),
		})
	}

	body := fiber.Map{
		"response":      output.Response,
		"user_id":       output.UserID,
		"tools_used":    output.ToolsUsed,
		"actions_taken": output.ActionsTaken,
	}
	if debug {
		body["tool_trace"] = output.ToolTrace
	}
	return c.JSON(body)
}

// GetHistory handles GET /api/coach/history/:user_id
//
// The orchestrator already persists both sides of every exchange, so the client
// does not have to keep the conversation in memory — which it cannot do anyway,
// since navigating away from the coach tab disposes the screen.
func (h *CoachHandler) GetHistory(c *fiber.Ctx) error {
	userID := c.Params("user_id")
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	limit := c.QueryInt("limit", 50)
	if limit < 1 || limit > 200 {
		limit = 50
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Newest first so the limit keeps the most recent exchange, then reversed
	// below so the client can render straight down the page.
	opts := options.Find().
		SetSort(bson.D{{Key: "created_at", Value: -1}}).
		SetLimit(int64(limit))

	cursor, err := h.chatMessagesCol.Find(ctx, bson.M{"user_id": userID}, opts)
	if err != nil {
		log.Printf("GetHistory: query failed for %s: %v", userID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch history"})
	}
	defer cursor.Close(ctx)

	var messages []models.ChatMessage
	if err := cursor.All(ctx, &messages); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to parse history"})
	}

	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	if messages == nil {
		messages = []models.ChatMessage{}
	}

	return c.JSON(fiber.Map{
		"messages": messages,
		"count":    len(messages),
	})
}
