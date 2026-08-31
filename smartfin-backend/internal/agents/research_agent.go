package agents

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

type ResearchAgent struct {
}

func NewResearchAgent() *ResearchAgent {
	return &ResearchAgent{}
}

// Research uses Gemini with Google Search Grounding to answer external financial questions
func (a *ResearchAgent) Research(ctx context.Context, query string) string {
	client, err := genai.NewClient(ctx, option.WithAPIKey(os.Getenv("GEMINI_API_KEY")))
	if err != nil {
		log.Printf("Error creating Gemini client for research: %v", err)
		return "Error: Unable to connect to search service."
	}
	defer client.Close()

	model := client.GenerativeModel("gemini-2.5-flash")
	model.SetTemperature(0.3) // Keep it factual

	// Search grounding tool temporarily removed due to SDK compilation issue
	// model.Tools = []*genai.Tool{
	// 	{
	// 		GoogleSearch: &genai.ToolGoogleSearch{},
	// 	},
	// }

	systemPrompt := `You are the Research Agent for SmartFin, a Thai personal finance app.
Your job is to answer the user's financial question accurately using your search capabilities.
Keep the answer concise, relevant to Thailand if applicable, and format numbers appropriately.`

	model.SystemInstruction = genai.NewUserContent(genai.Text(systemPrompt))

	resp, err := model.GenerateContent(ctx, genai.Text(query))
	if err != nil {
		log.Printf("Error calling Gemini Research Agent: %v", err)
		return "Error: Search failed."
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "No relevant information found."
	}

	responseText := fmt.Sprintf("%v", resp.Candidates[0].Content.Parts[0])
	return responseText
}
