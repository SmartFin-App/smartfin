package config

// GeminiModel is the model behind the scanner, the coach and the eval. Gemini 3
// models return a thought signature with each tool call that must be sent back,
// which is why the coach uses the google.golang.org/genai SDK's chat history.
// The lite model is used for its free-tier rate limit: 15 requests a minute,
// against 5 for the full-size flash models such as "gemini-3.5-flash".
const GeminiModel = "gemini-3.5-flash-lite"
