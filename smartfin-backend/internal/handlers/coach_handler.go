package handlers

import (
	"context"
	"log"
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/agents"
	"github.com/gofiber/fiber/v2"
)

// CoachHandler handles AI coach requests via the Gemini Agent Orchestrator
type CoachHandler struct {
	orchestrator *agents.Orchestrator
}

// NewCoachHandler creates a new CoachHandler
func NewCoachHandler() *CoachHandler {
	return &CoachHandler{
		orchestrator: agents.NewOrchestrator(),
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

	output, err := h.orchestrator.ProcessQuery(ctx, agents.AskCoachInput{
		UserID:  req.UserID,
		Message: req.Message,
		History: req.History,
	})
	if err != nil {
		log.Printf("Coach orchestrator error for user %s: %v", req.UserID, err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error":   "Failed to get AI response",
			"details": err.Error(),
		})
	}

	return c.JSON(fiber.Map{
		"response":      output.Response,
		"user_id":       output.UserID,
		"tools_used":    output.ToolsUsed,
		"actions_taken": output.ActionsTaken,
	})
}
