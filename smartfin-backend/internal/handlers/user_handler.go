package handlers

import (
	"context"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

// UserHandler structure
type UserHandler struct {
	collection *mongo.Collection
}

// NewUserHandler returns a configured handler
func NewUserHandler() *UserHandler {
	return &UserHandler{
		collection: config.GetCollection("users"),
	}
}

// CreateUser handles POST /api/users
func (h *UserHandler) CreateUser(c *fiber.Ctx) error {
	var req models.CreateUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	// Validate required fields
	if req.FirebaseUID == "" || req.Email == "" || req.Name == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid, email, and name must not be empty"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Check if user already exists
	var existingUser models.User
	err := h.collection.FindOne(ctx, bson.M{"firebase_uid": req.FirebaseUID}).Decode(&existingUser)
	if err == nil {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{"error": "User already exists"})
	} else if err != mongo.ErrNoDocuments {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Internal server error while verifying user"})
	}

	now := time.Now()

	// Create a new User struct from the request
	user := models.User{
		ID:              bson.NewObjectID(),
		FirebaseUID:     req.FirebaseUID,
		Name:            req.Name,
		Email:           req.Email,
		PhotoURL:        req.PhotoURL,
		MonthlyIncome:   req.MonthlyIncome,
		IncomeBracket:   req.IncomeBracket,
		CurrentStatus:   req.CurrentStatus,
		FinancialHealth: req.FinancialHealth,
		BudgetLimit:     req.BudgetLimit,
		WellnessScore:   75, // Default score
		Level:           1,  // Default level
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	// Insert into MongoDB
	_, err = h.collection.InsertOne(ctx, user)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create user"})
	}

	return c.Status(fiber.StatusCreated).JSON(user)
}

// GetUserByFirebaseUID handles GET /api/users/:firebase_uid
func (h *UserHandler) GetUserByFirebaseUID(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var user models.User
	err := h.collection.FindOne(ctx, bson.M{"firebase_uid": firebaseUID}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch user"})
	}

	return c.Status(fiber.StatusOK).JSON(user)
}

// UpdateUser handles PUT /api/users/:firebase_uid
func (h *UserHandler) UpdateUser(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	var updateData map[string]interface{}
	if err := c.BodyParser(&updateData); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	// Ensure we only update specific fields, safely ignore the immutable ones
	delete(updateData, "_id")
	delete(updateData, "firebase_uid")
	delete(updateData, "created_at")

	// Set updated_at directly
	updateData["updated_at"] = time.Now()

	update := bson.M{
		"$set": updateData,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	result, err := h.collection.UpdateOne(
		ctx,
		bson.M{"firebase_uid": firebaseUID},
		update,
	)

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update user"})
	}

	if result.MatchedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "User not found"})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{"message": "User updated successfully"})
}
