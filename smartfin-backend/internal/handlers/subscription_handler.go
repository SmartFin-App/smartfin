package handlers

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

const (
	maxSubscriptionName = 60
	maxSubscriptionNote = 200
	defaultBillCategory = "Bills"
)

// SubscriptionHandler serves the subscriptions and bills tracker. Paying a bill
// writes a transaction, so it holds the transactions and summaries collections too.
type SubscriptionHandler struct {
	collection             *mongo.Collection
	transactionsCollection *mongo.Collection
	summariesCollection    *mongo.Collection
}

func NewSubscriptionHandler() *SubscriptionHandler {
	return &SubscriptionHandler{
		collection:             config.GetCollection("subscriptions"),
		transactionsCollection: config.GetCollection("transactions"),
		summariesCollection:    config.GetCollection("monthly_summaries"),
	}
}

func formatBaht(amount int64) string {
	return summaries.Baht(amount)
}

// toSubscriptionResponse adds the derived display fields. Everything date-related
// is computed here in Thai time, so clients never convert the stored instant.
func toSubscriptionResponse(sub models.Subscription, now time.Time) models.SubscriptionResponse {
	days := summaries.DaysUntil(sub.NextDueDate, now)
	resp := models.SubscriptionResponse{
		Subscription:      sub,
		DueDate:           summaries.DueDateString(sub.NextDueDate),
		DaysUntilDue:      days,
		Status:            summaries.DueStatus(days, sub.Active),
		FormattedAmount:   formatBaht(sub.Amount),
		FormattedDueDate:  summaries.DueLabel(sub.NextDueDate, now),
		MonthlyEquivalent: summaries.MonthlyEquivalent(sub.Amount, sub.BillingCycle),
	}
	if next, err := summaries.AdvanceDue(sub.NextDueDate, sub.BillingCycle, sub.AnchorDay); err == nil {
		resp.NextDueAfterPayment = summaries.DueDateString(next)
	}
	return resp
}

func validSubscriptionName(name string) (string, bool) {
	name = strings.TrimSpace(name)
	n := utf8.RuneCountInString(name)
	return name, n > 0 && n <= maxSubscriptionName
}

// CreateSubscription handles POST /api/subscriptions
func (h *SubscriptionHandler) CreateSubscription(c *fiber.Ctx) error {
	var req struct {
		UserID       string `json:"user_id"`
		Name         string `json:"name"`
		Amount       int64  `json:"amount"`
		BillingCycle string `json:"billing_cycle"`
		NextDueDate  string `json:"next_due_date"`
		Category     string `json:"category"`
		Note         string `json:"note"`
		Active       *bool  `json:"active"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	userID := strings.TrimSpace(req.UserID)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}
	name, ok := validSubscriptionName(req.Name)
	if !ok {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Name must be 1 to 60 characters"})
	}
	if req.Amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Amount must be greater than 0"})
	}
	if !summaries.ValidCycle(req.BillingCycle) {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "billing_cycle must be 'weekly', 'monthly' or 'yearly'"})
	}
	// A past due date is allowed: the user may be adding a bill they have not
	// paid yet, which then shows as overdue.
	due, err := summaries.ParseDueDate(req.NextDueDate)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid next_due_date, expected YYYY-MM-DD"})
	}
	category := strings.TrimSpace(req.Category)
	if category == "" {
		category = defaultBillCategory
	}
	note := strings.TrimSpace(req.Note)
	if utf8.RuneCountInString(note) > maxSubscriptionNote {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Note must be 200 characters or fewer"})
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}

	now := time.Now()
	sub := models.Subscription{
		ID:           bson.NewObjectID(),
		UserID:       userID,
		Name:         name,
		Amount:       req.Amount,
		BillingCycle: req.BillingCycle,
		NextDueDate:  due,
		AnchorDay:    due.Day(),
		Category:     category,
		Note:         note,
		Active:       active,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if _, err := h.collection.InsertOne(ctx, sub); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create subscription"})
	}

	return c.Status(fiber.StatusCreated).JSON(toSubscriptionResponse(sub, now))
}

// GetSubscriptions handles GET /api/subscriptions/:user_id[?active=true]
//
// Bills come back soonest-due first, with totals the tracker header and the
// dashboard card show directly.
func (h *SubscriptionHandler) GetSubscriptions(c *fiber.Ctx) error {
	userID := strings.TrimSpace(c.Params("user_id"))
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	filter := bson.M{"user_id": userID}
	if c.Query("active") == "true" {
		filter["active"] = true
	}
	opts := options.Find().
		SetSort(bson.D{{Key: "next_due_date", Value: 1}}).
		SetLimit(200)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cursor, err := h.collection.Find(ctx, filter, opts)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch subscriptions"})
	}
	defer cursor.Close(ctx)

	var subs []models.Subscription
	if err := cursor.All(ctx, &subs); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Error parsing subscriptions"})
	}

	now := time.Now()
	responses := make([]models.SubscriptionResponse, 0, len(subs))
	var monthlyTotal, dueSoonTotal int64
	var activeCount, overdueCount, dueSoonCount int
	for _, sub := range subs {
		resp := toSubscriptionResponse(sub, now)
		responses = append(responses, resp)
		if !sub.Active {
			continue
		}
		activeCount++
		monthlyTotal += resp.MonthlyEquivalent
		switch resp.Status {
		case summaries.StatusOverdue:
			overdueCount++
			dueSoonTotal += sub.Amount
		case summaries.StatusDueToday, summaries.StatusDueSoon:
			dueSoonCount++
			dueSoonTotal += sub.Amount
		}
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{
		"today":          summaries.DueDateString(now),
		"subscriptions":  responses,
		"monthly_total":  monthlyTotal,
		"active_count":   activeCount,
		"overdue_count":  overdueCount,
		"due_soon_count": dueSoonCount,
		// Overdue plus due within DueSoonDays: what the user has to pay soon.
		"due_soon_total": dueSoonTotal,
	})
}

// UpdateSubscription handles PUT /api/subscriptions/:id
func (h *SubscriptionHandler) UpdateSubscription(c *fiber.Ctx) error {
	objID, err := bson.ObjectIDFromHex(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid subscription ID format"})
	}

	var req models.UpdateSubscriptionRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid request body"})
	}

	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	// The same rules CreateSubscription applies, for each field that was sent.
	if req.Name != nil {
		name, ok := validSubscriptionName(*req.Name)
		if !ok {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Name must be 1 to 60 characters"})
		}
		req.Name = &name
	}
	if req.Amount != nil && *req.Amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Amount must be greater than 0"})
	}
	if req.BillingCycle != nil && !summaries.ValidCycle(*req.BillingCycle) {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "billing_cycle must be 'weekly', 'monthly' or 'yearly'"})
	}
	if req.Category != nil {
		category := strings.TrimSpace(*req.Category)
		if category == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Category must not be empty"})
		}
		req.Category = &category
	}
	if req.Note != nil {
		note := strings.TrimSpace(*req.Note)
		if utf8.RuneCountInString(note) > maxSubscriptionNote {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Note must be 200 characters or fewer"})
		}
		req.Note = &note
	}

	updateData := req.ToUpdateFields()
	if req.NextDueDate != nil {
		due, err := summaries.ParseDueDate(*req.NextDueDate)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid next_due_date, expected YYYY-MM-DD"})
		}
		// Editing the date re-anchors the bill to that day of the month.
		updateData["next_due_date"] = due
		updateData["anchor_day"] = due.Day()
	}
	if len(updateData) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No update fields provided"})
	}
	updateData["updated_at"] = time.Now()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var updated models.Subscription
	err = h.collection.FindOneAndUpdate(ctx,
		bson.M{"_id": objID, "user_id": userID},
		bson.M{"$set": updateData},
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	).Decode(&updated)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Subscription not found"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to update subscription"})
	}

	return c.Status(fiber.StatusOK).JSON(toSubscriptionResponse(updated, time.Now()))
}

// DeleteSubscription handles DELETE /api/subscriptions/:id?user_id=…
//
// Transactions already logged by paying the bill are kept: they are real spending.
func (h *SubscriptionHandler) DeleteSubscription(c *fiber.Ctx) error {
	objID, err := bson.ObjectIDFromHex(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid subscription ID format"})
	}
	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	res, err := h.collection.DeleteOne(ctx, bson.M{"_id": objID, "user_id": userID})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to delete subscription"})
	}
	if res.DeletedCount == 0 {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Subscription not found"})
	}

	return c.Status(fiber.StatusOK).JSON(fiber.Map{"message": "Subscription deleted successfully"})
}

// MarkPaid handles POST /api/subscriptions/:id/pay
//
// Body: {user_id, expected_due_date}. Paying logs the bill as an expense for today
// and moves the due date forward one cycle.
//
// The order is what makes a double tap or a network retry harmless. The due date
// is advanced first, with a conditional update that only matches while the bill
// is still at the due date the client saw — so of two identical requests exactly
// one matches, and the other gets 409 before anything is booked. The transaction
// is inserted only after that; if the insert fails, the date is put back.
func (h *SubscriptionHandler) MarkPaid(c *fiber.Ctx) error {
	objID, err := bson.ObjectIDFromHex(c.Params("id"))
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid subscription ID format"})
	}
	userID := ownerFromRequest(c)
	if userID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "user_id is required"})
	}
	var body struct {
		ExpectedDueDate string `json:"expected_due_date"`
	}
	_ = c.BodyParser(&body)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	owned := bson.M{"_id": objID, "user_id": userID}
	var sub models.Subscription
	if err := h.collection.FindOne(ctx, owned).Decode(&sub); err != nil {
		if err == mongo.ErrNoDocuments {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "Subscription not found"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to fetch subscription"})
	}

	now := time.Now()
	conflict := func(msg string, current models.Subscription) error {
		return c.Status(fiber.StatusConflict).JSON(fiber.Map{
			"error":        msg,
			"subscription": toSubscriptionResponse(current, now),
		})
	}

	if !sub.Active {
		return conflict("This bill is paused", sub)
	}
	if body.ExpectedDueDate != "" {
		expected, err := summaries.ParseDueDate(body.ExpectedDueDate)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Invalid expected_due_date, expected YYYY-MM-DD"})
		}
		if !expected.Equal(summaries.DateOf(sub.NextDueDate)) {
			return conflict("This bill was already marked paid", sub)
		}
	}

	newDue, err := summaries.AdvanceDue(sub.NextDueDate, sub.BillingCycle, sub.AnchorDay)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "This bill has an invalid billing cycle"})
	}

	advance, err := h.collection.UpdateOne(ctx,
		bson.M{"_id": objID, "user_id": userID, "active": true, "next_due_date": sub.NextDueDate},
		bson.M{"$set": bson.M{"next_due_date": newDue, "last_paid_at": now, "updated_at": now}},
	)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to mark bill as paid"})
	}
	if advance.MatchedCount == 0 {
		// Another request paid (or paused) it between our read and this write.
		current := sub
		_ = h.collection.FindOne(ctx, owned).Decode(&current)
		return conflict("This bill was already marked paid", current)
	}

	tx := models.Transaction{
		ID:        bson.NewObjectID(),
		UserID:    userID,
		Merchant:  sub.Name,
		Amount:    sub.Amount,
		Type:      "expense",
		Category:  sub.Category,
		Source:    "subscription",
		Date:      now,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if _, err := h.transactionsCollection.InsertOne(ctx, tx); err != nil {
		revert := bson.M{"$set": bson.M{"next_due_date": sub.NextDueDate, "updated_at": time.Now()}}
		if sub.LastPaidAt != nil {
			revert["$set"].(bson.M)["last_paid_at"] = *sub.LastPaidAt
		} else {
			revert["$unset"] = bson.M{"last_paid_at": ""}
		}
		_, _ = h.collection.UpdateOne(ctx, bson.M{"_id": objID, "user_id": userID, "next_due_date": newDue}, revert)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to log the payment"})
	}

	summaries.InvalidateFor(ctx, h.summariesCollection, userID, tx.Date)

	sub.NextDueDate = newDue
	sub.LastPaidAt = &now
	sub.UpdatedAt = now

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message": fmt.Sprintf("Paid %s %s — next due %s", sub.Name, formatBaht(sub.Amount), newDue.In(summaries.Zone).Format("Jan 2")),
		"transaction": models.TransactionResponse{
			Transaction:     tx,
			FormattedAmount: formatAmount(tx.Amount, tx.Type),
			FormattedDate:   formatDate(tx.Date),
		},
		"subscription": toSubscriptionResponse(sub, now),
	})
}
