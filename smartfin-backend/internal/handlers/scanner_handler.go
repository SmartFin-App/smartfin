package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
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
	client, err := genai.NewClient(ctx, option.WithAPIKey(os.Getenv("GEMINI_API_KEY")))
	if err != nil {
		log.Printf("Error creating Gemini client: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to create AI client"})
	}
	defer client.Close()

	// Use gemini-1.5-flash model
	model := client.GenerativeModel("gemini-2.5-flash")
	model.SetTemperature(0)

	// Build the prompt
	prompt := `Analyze this receipt image and extract the following information. 
Return ONLY a valid JSON object with no markdown, no code blocks, just pure JSON.

Extract:
- merchant_name: the store or restaurant name (if Thai text, transliterate to English)
- total_amount: the final total amount as an integer number only (no currency symbols, no decimals)
- date: the date in YYYY-MM-DD format (if not found use today's date)
- confidence: your confidence score from 0.0 to 1.0

Example response:
{"merchant_name":"Starbucks","total_amount":150,"date":"2026-04-01","confidence":0.95}

If you cannot read the receipt clearly, still return your best guess with a low confidence score.`

	// Send image + prompt to Gemini
	imageData := genai.Blob{MIMEType: mimeType, Data: imageBytes}
	resp, err := model.GenerateContent(ctx, genai.Text(prompt), imageData)
	if err != nil {
		log.Printf("Error calling Gemini: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "Failed to analyze receipt"})
	}

	// Extract the response text
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "No response from AI"})
	}
	responseText := fmt.Sprintf("%v", resp.Candidates[0].Content.Parts[0])
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

	confidence := 0.0
	if conf, ok := result["confidence"].(float64); ok {
		confidence = conf
	}

	log.Printf("Extracted - Merchant: %s, Amount: %d, Date: %s, Confidence: %.2f", merchant, amount, date, confidence)

	return c.JSON(fiber.Map{
		"merchant":   merchant,
		"amount":     amount,
		"date":       date,
		"confidence": confidence,
		"raw_text":   responseText,
	})
}
