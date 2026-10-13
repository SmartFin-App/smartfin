package handlers

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/gofiber/fiber/v2"
	"google.golang.org/genai"
)

// ScannerHandler handles receipt scanning via Gemini Vision
type ScannerHandler struct{}

// NewScannerHandler creates a new ScannerHandler
func NewScannerHandler() *ScannerHandler {
	return &ScannerHandler{}
}

// ProcessReceipt handles POST /api/scanner/process
func (h *ScannerHandler) ProcessReceipt(c *fiber.Ctx) error {
	// Parse the multipart form
	form, err := c.MultipartForm()
	if err != nil {
		log.Printf("Error at step 1 (parse multipart form): %v", err)
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "Failed to parse multipart form"})
	}

	userID := ""
	if vals := form.Value["user_id"]; len(vals) > 0 {
		userID = vals[0]
	}
	log.Printf("Processing receipt for user: %s", userID)

	// Get image file from form
	files := form.File["image"]
	if len(files) == 0 {
		log.Printf("Error at step 2 (get image): no image file in form")
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "No image file provided"})
	}

	fileHeader := files[0]

	// Open and read the image bytes
	file, err := fileHeader.Open()
	if err != nil {
		log.Printf("Error at step 3 (open image file): %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to open image file"})
	}
	defer file.Close()

	imageBytes, err := io.ReadAll(file)
	if err != nil {
		log.Printf("Error at step 4 (read image bytes): %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to read image file"})
	}

	// Determine MIME type from file extension
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	mimeType := "image/jpeg"
	if ext == ".png" {
		mimeType = "image/png"
	}
	log.Printf("Image size: %d bytes, MIME type: %s", len(imageBytes), mimeType)

	// Create Gemini client
	ctx := context.Background()
	client, err := genai.NewClient(ctx, &genai.ClientConfig{APIKey: os.Getenv("GEMINI_API_KEY"), Backend: genai.BackendGeminiAPI})
	if err != nil {
		log.Printf("Error creating Gemini client: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create AI client"})
	}

	// Build the prompt
	prompt := `Analyze this image, which is either a retail receipt or a Thai mobile banking payment confirmation slip (e-slip from PromptPay, K PLUS, SCB EASY, Krungthai NEXT, Bangkok Bank, etc.).
Extract the following key financial information. Return ONLY a valid JSON object with no markdown, no code blocks, just pure JSON.

Extract:
- merchant_name: the store, merchant, or recipient name (if written in Thai, transliterate to clear English, e.g. "Somchai Market" or "KFC Central World")
- total_amount: the final transaction or payment amount as an integer number only (no currency symbols, no decimals, e.g. 150)
- date: the date in YYYY-MM-DD format (if only DD/MM/YYYY or Thai Buddhist year like 2567/2569 is shown, convert properly to Gregorian YYYY-MM-DD; if not found use today's date)
- category: what the money was spent on, as exactly one of: Food, Transport, Groceries, Shopping, Bills, Health, Entertainment, Other. Judge it from what the merchant sells: restaurants, cafes, street food and food delivery are Food; BTS, MRT, taxis, ride-hailing, fuel and tolls are Transport; supermarkets, convenience stores and fresh markets are Groceries; clothing, electronics, department stores and online marketplaces are Shopping; electricity, water, internet, phone, rent and condo fees are Bills; pharmacies, clinics and hospitals are Health; cinemas, streaming, games and events are Entertainment. If the recipient is a person's name, or nothing shows what was bought, use Other rather than guessing.
- confidence: your confidence score from 0.0 to 1.0

Example response:
{"merchant_name":"Lotus's","total_amount":350,"date":"2026-04-01","category":"Groceries","confidence":0.95}

If you cannot read the image clearly, still return your best guess with a lower confidence score.`

	// Send image + prompt to Gemini
	contents := []*genai.Content{
		genai.NewContentFromParts([]*genai.Part{
			genai.NewPartFromText(prompt),
			genai.NewPartFromBytes(imageBytes, mimeType),
		}, genai.RoleUser),
	}
	resp, err := client.Models.GenerateContent(ctx, config.GeminiModel, contents,
		&genai.GenerateContentConfig{Temperature: genai.Ptr[float32](0)})
	if err != nil {
		log.Printf("Error calling Gemini: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to analyze receipt"})
	}

	// Extract the response text
	responseText := resp.Text()
	if responseText == "" {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "No response from AI"})
	}
	log.Printf("Gemini response: %s", responseText)

	// Clean the response and parse JSON
	responseText = strings.TrimSpace(responseText)
	responseText = strings.TrimPrefix(responseText, "```json")
	responseText = strings.TrimPrefix(responseText, "```")
	responseText = strings.TrimSuffix(responseText, "```")
	responseText = strings.TrimSpace(responseText)

	var result map[string]interface{}
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		log.Printf("Error parsing Gemini JSON response: %v", err)
		log.Printf("Raw response: %s", responseText)
		// Return defaults if parsing fails
		return c.JSON(fiber.Map{
			"merchant":   "Unknown Merchant",
			"amount":     0,
			"date":       time.Now().Format("2006-01-02"),
			"category":   "Other",
			"confidence": 0.0,
			"raw_text":   responseText,
		})
	}

	// Extract and return the fields
	merchant := "Unknown Merchant"
	if m, ok := result["merchant_name"].(string); ok && m != "" {
		merchant = m
	}

	amount := 0
	if a, ok := result["total_amount"].(float64); ok {
		amount = int(a)
	}

	date := time.Now().Format("2006-01-02")
	if d, ok := result["date"].(string); ok && d != "" {
		date = d
	}

	// The verify screen preselects this; the user still confirms it.
	rawCategory, _ := result["category"].(string)
	category := models.NormalizeCategory(rawCategory)

	confidence := 0.0
	if conf, ok := result["confidence"].(float64); ok {
		confidence = conf
	}

	log.Printf("Extracted - Merchant: %s, Amount: %d, Date: %s, Category: %s, Confidence: %.2f", merchant, amount, date, category, confidence)

	return c.JSON(fiber.Map{
		"merchant":   merchant,
		"amount":     amount,
		"date":       date,
		"category":   category,
		"confidence": confidence,
		"raw_text":   responseText,
	})
}
