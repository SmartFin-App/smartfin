package routes

import (
	"context"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/handlers"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/v2/bson"
)

// SetupRoutes registers all API routes with the Fiber app
func SetupRoutes(app *fiber.App) {
	// Create handler instances
	userHandler := handlers.NewUserHandler()
	transactionHandler := handlers.NewTransactionHandler()
	scannerHandler := handlers.NewScannerHandler()
	coachHandler := handlers.NewCoachHandler()
	summaryHandler := handlers.NewSummaryHandler()
	photoHandler := handlers.NewPhotoHandler()

	// Setup an API group with prefix /api
	api := app.Group("/api")

	// User routes under /api/users
	users := api.Group("/users")
	users.Post("", userHandler.CreateUser)
	users.Get("/:firebase_uid", userHandler.GetUserByFirebaseUID)
	users.Put("/:firebase_uid", userHandler.UpdateUser)
	users.Patch("/:firebase_uid", userHandler.UpdateUser) // alias for Flutter PATCH calls
	users.Delete("/:firebase_uid", userHandler.DeleteUser)

	// Profile photo (stored in GridFS, referenced by a relative path)
	users.Post("/:firebase_uid/photo", photoHandler.UploadPhoto)
	users.Get("/:firebase_uid/photo", photoHandler.GetPhoto)
	users.Delete("/:firebase_uid/photo", photoHandler.DeletePhoto)

	// Transaction routes under /api/transactions
	transactions := api.Group("/transactions")
	transactions.Post("", transactionHandler.CreateTransaction)
	transactions.Get("/:user_id", transactionHandler.GetTransactions)
	transactions.Get("/detail/:id", transactionHandler.GetTransactionByID)
	transactions.Get("/summary/:user_id", transactionHandler.GetTransactionSummary)
	transactions.Put("/:id", transactionHandler.UpdateTransaction)
	transactions.Delete("/:id", transactionHandler.DeleteTransaction)

	// Scanner routes under /api/scanner
	scanner := api.Group("/scanner")
	scanner.Post("/process", scannerHandler.ProcessReceipt)

	// Coach routes under /api/coach
	coach := api.Group("/coach")
	coach.Post("/ask", coachHandler.AskCoach)
	coach.Get("/history/:user_id", coachHandler.GetHistory)

	// Summary routes under /api/summary
	summary := api.Group("/summary")
	summary.Get("/:user_id/history", summaryHandler.GetSummaryHistory)
	summary.Get("/:user_id/savings-goal", summaryHandler.GetSavingsProgress)
	summary.Get("/:user_id", summaryHandler.GetMonthlySummary)

	// Admin routes
	app.Post("/admin/seed-transactions", func(c *fiber.Ctx) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		collection := config.GetCollection("transactions")

		userID := c.Query("user_id")
		if userID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "user_id query param required"})
		}

		transactions := []interface{}{
			// November 2025
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Big C Supermarket", Amount: 2800, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2025, 11, 3, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Grab Ride", Amount: 350, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2025, 11, 5, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "MK Restaurant", Amount: 1200, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2025, 11, 8, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "True Move H", Amount: 599, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2025, 11, 10, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Central Department Store", Amount: 3500, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2025, 11, 15, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Starbucks Coffee", Amount: 280, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2025, 11, 18, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Bumrungrad Hospital", Amount: 1500, Type: "expense", Category: "Health", Source: "manual", Date: time.Date(2025, 11, 22, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Line MAN", Amount: 450, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2025, 11, 25, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Freelance Payment", Amount: 15000, Type: "income", Category: "Salary", Source: "manual", Date: time.Date(2025, 11, 28, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			// December 2025
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Lotus's", Amount: 3200, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2025, 12, 2, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Netflix", Amount: 419, Type: "expense", Category: "Entertainment", Source: "manual", Date: time.Date(2025, 12, 5, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Siam Paragon", Amount: 5800, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2025, 12, 10, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Grab Ride", Amount: 420, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2025, 12, 12, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Yakiniku Like", Amount: 890, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2025, 12, 15, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Christmas Gift", Amount: 2500, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2025, 12, 20, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "AIS Mobile", Amount: 799, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2025, 12, 22, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Year End Bonus", Amount: 25000, Type: "income", Category: "Salary", Source: "manual", Date: time.Date(2025, 12, 28, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			// January 2026
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Big C Supermarket", Amount: 2600, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Starbucks Coffee", Amount: 320, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 1, 6, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "BTS Rabbit Card Top Up", Amount: 500, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2026, 1, 8, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "New Year Clothes", Amount: 4200, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2026, 1, 10, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Thai Airways", Amount: 8900, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2026, 1, 15, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Chiangmai Hotel", Amount: 3200, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2026, 1, 16, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "True Move H", Amount: 599, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2026, 1, 20, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Line MAN", Amount: 380, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 1, 25, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			// February 2026
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Lotus's", Amount: 2900, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2026, 2, 2, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Valentine Dinner", Amount: 2200, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 2, 14, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Grab Ride", Amount: 290, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2026, 2, 16, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Netflix", Amount: 419, Type: "expense", Category: "Entertainment", Source: "manual", Date: time.Date(2026, 2, 18, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Samitivej Hospital", Amount: 2800, Type: "expense", Category: "Health", Source: "manual", Date: time.Date(2026, 2, 20, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "AIS Mobile", Amount: 799, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2026, 2, 22, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Freelance Payment", Amount: 20000, Type: "income", Category: "Salary", Source: "manual", Date: time.Date(2026, 2, 25, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			// March 2026
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Big C Supermarket", Amount: 3100, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2026, 3, 3, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Starbucks Coffee", Amount: 350, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Grab Ride", Amount: 410, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2026, 3, 8, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Central World", Amount: 6500, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2026, 3, 12, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "True Move H", Amount: 599, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2026, 3, 15, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Yakiniku Like", Amount: 950, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 3, 18, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Netflix", Amount: 419, Type: "expense", Category: "Entertainment", Source: "manual", Date: time.Date(2026, 3, 20, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Pharmacy", Amount: 680, Type: "expense", Category: "Health", Source: "manual", Date: time.Date(2026, 3, 25, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			// April 2026
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Lotus's", Amount: 2750, Type: "expense", Category: "Groceries", Source: "manual", Date: time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Starbucks Coffee", Amount: 280, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 4, 2, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Grab Ride", Amount: 180, Type: "expense", Category: "Transport", Source: "manual", Date: time.Date(2026, 4, 3, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Songkran Clothes", Amount: 3200, Type: "expense", Category: "Shopping", Source: "manual", Date: time.Date(2026, 4, 5, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "MK Restaurant", Amount: 1100, Type: "expense", Category: "Food", Source: "manual", Date: time.Date(2026, 4, 8, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "Netflix", Amount: 419, Type: "expense", Category: "Entertainment", Source: "manual", Date: time.Date(2026, 4, 10, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
			models.Transaction{ID: bson.NewObjectID(), UserID: userID, Merchant: "True Move H", Amount: 599, Type: "expense", Category: "Bills", Source: "manual", Date: time.Date(2026, 4, 12, 0, 0, 0, 0, time.UTC), CreatedAt: time.Now(), UpdatedAt: time.Now()},
		}

		result, err := collection.InsertMany(ctx, transactions)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		return c.JSON(fiber.Map{
			"inserted": len(result.InsertedIDs),
			"message":  "Seed data inserted successfully",
		})
	})

	app.Delete("/admin/reset-summaries", summaryHandler.ResetSummaries)
	app.Delete("/admin/reset-transactions", summaryHandler.DeleteAllTransactions)
}
