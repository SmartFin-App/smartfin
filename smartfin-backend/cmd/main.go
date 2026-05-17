package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/joho/godotenv"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/routes"
)

func main() {
	// Load the .env file
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: Error loading .env file")
	}

	// Connect to MongoDB
	config.ConnectDB()

	// Create a new Fiber app instance
	app := fiber.New(fiber.Config{
		AppName:     "SmartFin API",
		JSONEncoder: json.Marshal,
		JSONDecoder: json.Unmarshal,
	})

	// Add middleware
	// fiber.cors — allow all origins for now
	app.Use(cors.New())
	// fiber.logger — logs every request to the terminal
	app.Use(logger.New())
	// fiber.recover — recovers from panics so the server doesn't crash
	app.Use(recover.New())

	// Add a health check route
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":  "ok",
			"message": "SmartFin API is running",
		})
	})

	// Register all API routes
	routes.SetupRoutes(app)

	// Read the PORT from .env
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000" // fallback
	}

	// Print startup message
	fmt.Printf("SmartFin API running on port %s\n", port)

	// Start the server
	err = app.Listen(":" + port)
	if err != nil {
		log.Fatal("Failed to start server: ", err)
	}
}
