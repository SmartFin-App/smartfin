package handlers

import (
	"context"
	"log"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

// UserHandler structure
type UserHandler struct {
	collection              *mongo.Collection
	transactionsCollection  *mongo.Collection
	summariesCollection     *mongo.Collection
	chatMessagesCollection  *mongo.Collection
	subscriptionsCollection *mongo.Collection
}

// NewUserHandler returns a configured handler
func NewUserHandler() *UserHandler {
	return &UserHandler{
		collection:              config.GetCollection("users"),
		transactionsCollection:  config.GetCollection("transactions"),
		summariesCollection:     config.GetCollection("monthly_summaries"),
		chatMessagesCollection:  config.GetCollection("chat_messages"),
		subscriptionsCollection: config.GetCollection("subscriptions"),
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

	var req models.UpdateUserRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	// Only the fields declared on UpdateUserRequest are writable, so _id,
	// firebase_uid and created_at are unreachable by construction.
	updateData := req.ToUpdateFields()
	if len(updateData) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No updatable fields provided"})
	}

	// Amounts are Thai Baht and never negative.
	for _, field := range []string{"monthly_income", "budget_limit", "savings_goal"} {
		if v, ok := updateData[field].(int64); ok && v < 0 {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": field + " must not be negative"})
		}
	}

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

// DeleteUser handles DELETE /api/users/:firebase_uid
//
// This erases the account and everything attached to it: transactions, monthly
// summaries, coach conversations and tracked subscriptions. It is irreversible and there is no soft
// delete, so it must only be reachable behind a client-side reauthentication.
//
// NOTE: like the rest of this API it does not verify a Firebase token, so
// possession of a UID is currently enough to wipe that user. Whoever adds token
// verification should treat this handler as the first thing to cover.
func (h *UserHandler) DeleteUser(c *fiber.Ctx) error {
	firebaseUID := c.Params("firebase_uid")
	if firebaseUID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "firebase_uid is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Delete the owned records first. If this half fails the account still exists,
	// which is recoverable; an orphaned pile of transactions under a deleted user
	// is not.
	owned := bson.M{"user_id": firebaseUID}
	deleted := map[string]int64{}

	for name, col := range map[string]*mongo.Collection{
		"transactions":  h.transactionsCollection,
		"summaries":     h.summariesCollection,
		"chat_messages": h.chatMessagesCollection,
		"subscriptions": h.subscriptionsCollection,
	} {
		res, err := col.DeleteMany(ctx, owned)
		if err != nil {
			log.Printf("DeleteUser: failed clearing %s for %s: %v", name, firebaseUID, err)
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to delete account data",
			})
		}
		deleted[name] = res.DeletedCount
	}

	res, err := h.collection.DeleteOne(ctx, bson.M{"firebase_uid": firebaseUID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to delete user"})
	}
	if res.DeletedCount == 0 {
		// The owned records are already gone, so report success rather than 404:
		// the caller's goal (no data for this UID) now holds either way.
		log.Printf("DeleteUser: no profile document for %s, owned records cleared", firebaseUID)
	}

	log.Printf("DeleteUser: erased %s (%d transactions, %d summaries, %d messages, %d subscriptions)",
		firebaseUID, deleted["transactions"], deleted["summaries"], deleted["chat_messages"], deleted["subscriptions"])

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"message":       "Account deleted successfully",
		"transactions":  deleted["transactions"],
		"summaries":     deleted["summaries"],
		"messages":      deleted["chat_messages"],
		"subscriptions": deleted["subscriptions"],
	})
}
