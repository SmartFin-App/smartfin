package routes

import (
	"context"
	"os"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/handlers"
	"github.com/gofiber/fiber/v2"
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
	subscriptionHandler := handlers.NewSubscriptionHandler()

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
	transactions.Get("/duplicates/:user_id", transactionHandler.FindPossibleDuplicates)
	transactions.Put("/:id", transactionHandler.UpdateTransaction)
	transactions.Delete("/:id", transactionHandler.DeleteTransaction)

	// Subscriptions & bills tracker under /api/subscriptions
	subscriptions := api.Group("/subscriptions")
	subscriptions.Post("", subscriptionHandler.CreateSubscription)
	subscriptions.Post("/:id/pay", subscriptionHandler.MarkPaid)
	subscriptions.Get("/:user_id", subscriptionHandler.GetSubscriptions)
	subscriptions.Put("/:id", subscriptionHandler.UpdateSubscription)
	subscriptions.Delete("/:id", subscriptionHandler.DeleteSubscription)

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
	summary.Get("/:user_id", summaryHandler.GetMonthlySummary)

	// Admin routes: seed and wipe data, so they need the X-Admin-Key header
	// (see adminGuard). Without ADMIN_API_KEY set they are switched off.
	admin := app.Group("/admin", adminGuard(os.Getenv("ADMIN_API_KEY")))
	admin.Post("/seed-transactions", func(c *fiber.Ctx) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		collection := config.GetCollection("transactions")

		userID := c.Query("user_id")
		if userID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "user_id query param required"})
		}

		result, err := collection.InsertMany(ctx, demoTransactions(userID, time.Now()))
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		return c.JSON(fiber.Map{
			"inserted": len(result.InsertedIDs),
			"message":  "Seed data inserted successfully",
		})
	})

	admin.Delete("/reset-summaries", summaryHandler.ResetSummaries)
	admin.Delete("/reset-transactions", summaryHandler.DeleteAllTransactions)
}
