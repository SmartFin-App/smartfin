package agents

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"google.golang.org/genai"
)

// Orchestrator coordinates multi-agent reasoning, tool dispatch, and generation
type Orchestrator struct {
	retrievalAgent  *RetrievalAgent
	actionAgent     *ActionAgent
	researchAgent   *ResearchAgent
	chatMessagesCol *mongo.Collection
	usersCol        *mongo.Collection
}

// NewOrchestrator creates a new GeminiAgentOrchestrator
func NewOrchestrator() *Orchestrator {
	return &Orchestrator{
		retrievalAgent:  NewRetrievalAgent(),
		actionAgent:     NewActionAgent(),
		researchAgent:   NewResearchAgent(),
		chatMessagesCol: config.GetCollection("chat_messages"),
		usersCol:        config.GetCollection("users"),
	}
}

// AskCoachInput contains user input and dialog history
type AskCoachInput struct {
	UserID  string
	Message string
	History []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	// Debug records every tool call, with its arguments and result, in
	// AskCoachOutput.ToolTrace. It exists for the evaluation harness (cmd/eval),
	// which needs to tell a retrieval failure from a generation failure.
	Debug bool
}

// AskCoachOutput contains the grounded response and orchestration metadata
type AskCoachOutput struct {
	Response     string           `json:"response"`
	UserID       string           `json:"user_id"`
	ToolsUsed    []string         `json:"tools_used,omitempty"`
	ActionsTaken []map[string]any `json:"actions_taken,omitempty"`
	ToolTrace    []ToolTrace      `json:"tool_trace,omitempty"`
	// Nudged is true when the first reply only announced a lookup and the loop
	// asked the model once more to actually call the tool.
	Nudged bool `json:"nudged,omitempty"`
}

// stallPhrases mark a reply that only promises to look something up. Gemini
// sometimes sends one instead of calling a tool, and the loop used to take it as
// the final answer — the user got "give me a moment…" and nothing after it. The
// coach evaluation traced 10 of 12 failures in its second run to this.
var stallPhrases = []string{
	"a moment", "let me check", "let me look", "let me fetch", "let me pull", "let me gather", "let me get",
	"i'll check", "i will check", "i'll look", "i'll fetch", "i'll gather", "i'll pull", "i'll get that",
	"checking your", "looking up your", "please hold", "bear with me",
	"สักครู่", "ขอตรวจสอบ", "กำลังตรวจสอบ", "ขอเช็ค", "ขอเรียกดู", "ขอดูข้อมูล", "เดี๋ยว",
}

const stallNudge = "You have not called any tool yet. Do not announce that you will check — call the tool(s) you need now, then answer with the real figures, in the same language as my question."

// looksLikeStall reports whether a reply without tool calls is only a short
// promise to check. Real answers without tools (an off-topic redirect, the budget
// from the profile) do not use these phrases, and long replies are never treated
// as stalls.
func looksLikeStall(text string) bool {
	t := strings.ToLower(strings.TrimSpace(text))
	if t == "" || utf8.RuneCountInString(t) > 400 {
		return false
	}
	for _, p := range stallPhrases {
		if strings.Contains(t, p) {
			return true
		}
	}
	return false
}

// ToolTrace is one tool call as the model made it and as it was answered.
// Result is exactly what was sent back to Gemini.
type ToolTrace struct {
	Turn   int            `json:"turn"`
	Name   string         `json:"name"`
	Args   map[string]any `json:"args"`
	Result map[string]any `json:"result,omitempty"`
	Error  string         `json:"error,omitempty"`
	Ms     int64          `json:"ms"`
}

// ProcessQuery runs the agentic RAG orchestration loop
func (o *Orchestrator) ProcessQuery(ctx context.Context, input AskCoachInput) (*AskCoachOutput, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY is not configured")
	}

	geminiClient, err := genai.NewClient(ctx, &genai.ClientConfig{APIKey: apiKey, Backend: genai.BackendGeminiAPI})
	if err != nil {
		return nil, fmt.Errorf("failed to create Gemini client: %w", err)
	}

	// 1. Fetch user profile context for initial system prompt grounding
	var user models.User
	hasProfile := o.usersCol.FindOne(ctx, bson.M{"firebase_uid": input.UserID}).Decode(&user) == nil

	// The model has no clock of its own. Without this it cannot resolve "this
	// month", "yesterday" or "last week", and it cannot place the timestamps that
	// come back from get_recent_conversations — it was left inferring the date
	// from its training data.
	now := time.Now().In(summaries.Zone)
	userContext := fmt.Sprintf(
		"Current date and time: %s (Thailand, UTC+07:00)\nCurrent month: %s\n\n%s",
		now.Format("Monday, 2 January 2006, 15:04"), summaries.StringOf(now),
		describeProfile(user, hasProfile),
	)

	systemInstruction := fmt.Sprintf(`You are Kwak, SmartFin's AI Coach — a friendly, highly intelligent AI financial coach for a Thai user. Your name comes from แมวกวัก, the Thai beckoning lucky cat.
Use your name only when introducing yourself or when asked who you are, and call yourself the AI Coach otherwise; do not sign or open every reply with it.
You speak in a warm, encouraging tone and occasionally use the paw print emoji 🐾.
You are equipped with specialized multi-agent tools to query data, execute financial actions, or search the web.

%s

Follow this Reasoning Process:
1. ORCHESTRATE: Analyze what information or action the user requires:
   - Need personal financial data? Call FinancialRetrievalAgent tools (get_budget_summary, get_transactions, get_spending_insights, get_subscriptions, get_recent_conversations).
   - Asked about bad, wasteful or unnecessary expenses, or where to cut back? Call get_spending_insights rather than judging a transaction list yourself.
   - Need to perform a financial action? Call FinancialActionAgent tools (update_budget_limit, add_transaction).
   - Need external market/interest/tax/economic facts? Call FinancialResearchAgent (web_search).
2. OBSERVE: Review the returned observations. If you still lack necessary details, invoke additional tools.
3. GROUND & ANSWER: Once you have sufficient information, synthesize a clear, helpful, personalized answer.
   - Format amounts in Thai Baht (฿) with no decimals.
   - All dates and timestamps you receive are already Thai local time (UTC+07:00). Use the current date above when resolving "today", "this month" or "last week" — never guess it.
   - Keep answers concise (3-4 sentences) unless user asks for detailed analysis.
   - SmartFin tracks spending only: expenses and the monthly budget. It records no income and no savings goals, so never state what the user earned or saved. If asked, say the app tracks spending and budget, and answer with those instead.
   - If an action was completed, confirm it clearly to the user.
   - Current interest rates, prices, inflation figures and tax allowances change. State one only if it came from a web_search result in this conversation, and name its source. If web_search reports it is unavailable, say you could not check the latest figure and suggest where to confirm it — never supply a number from memory.
   - Subscriptions and bills are tracked by the user in the app. If the user says they paid a bill, tell them to tap "Mark paid" in Subscriptions & Bills rather than calling add_transaction — that logs the expense and also moves the next due date.
   - When discussing bad or wasteful spending, call the items "worth reviewing" rather than bad, give the reason and figures for each, and suggest one concrete step. Never describe Bills, Groceries, Health or Transport spending as bad.
   - Gently redirect non-financial topics back to financial health.`, userContext)

	// Model setup, with the agent tools registered
	genConfig := &genai.GenerateContentConfig{
		Temperature:       genai.Ptr[float32](0.5),
		SystemInstruction: genai.NewContentFromText(systemInstruction, genai.RoleUser),
		Tools: []*genai.Tool{
			{
				FunctionDeclarations: o.getFunctionDeclarations(),
			},
		},
	}

	// Load previous history
	var history []*genai.Content
	for _, h := range input.History {
		if h.Role == "user" || h.Role == "model" {
			history = append(history, genai.NewContentFromText(h.Content, genai.Role(h.Role)))
		}
	}

	// The chat keeps each model turn exactly as returned, thought signatures
	// included; Gemini 3 rejects a tool response whose call has lost its signature.
	chat, err := geminiClient.Chats.Create(ctx, config.GeminiModel, genConfig, history)
	if err != nil {
		return nil, fmt.Errorf("failed to start Gemini chat: %w", err)
	}

	toolsUsedSet := make(map[string]bool)
	var actionsTaken []map[string]any
	var trace []ToolTrace
	var finalResponse string
	nudged := false

	// Send initial user query
	resp, err := chat.Send(ctx, genai.NewPartFromText(input.Message))
	if err != nil {
		return nil, fmt.Errorf("gemini send message failed: %w", err)
	}

	// Multi-turn Agentic loop (max 5 iterations to avoid runaway loops)
	for turn := 0; turn < 5; turn++ {
		if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil {
			break
		}

		candidate := resp.Candidates[0]
		var functionCalls []*genai.FunctionCall
		var textParts []string

		for _, part := range candidate.Content.Parts {
			switch {
			case part == nil:
			case part.FunctionCall != nil:
				functionCalls = append(functionCalls, part.FunctionCall)
			case part.Text != "" && !part.Thought:
				textParts = append(textParts, part.Text)
			}
		}

		// If no tool calls were requested, we have arrived at the final answer —
		// unless the first reply only promised to check. Nudge once to make the
		// call; if the nudge itself fails, fall back to the text we have.
		if len(functionCalls) == 0 {
			text := strings.Join(textParts, " ")
			if turn == 0 && !nudged && looksLikeStall(text) {
				nudged = true
				log.Printf("Orchestrator: first reply announced a lookup without calling a tool; nudging once")
				next, nerr := chat.Send(ctx, genai.NewPartFromText(stallNudge))
				if nerr == nil {
					resp = next
					continue
				}
				log.Printf("Orchestrator: nudge failed: %v", nerr)
			}
			finalResponse = text
			break
		}

		// Execute all requested tool calls and gather responses
		var functionResponses []*genai.Part
		for _, call := range functionCalls {
			toolsUsedSet[call.Name] = true
			log.Printf("Orchestrator: Executing tool %s with args: %+v", call.Name, call.Args)

			started := time.Now()
			result, actionRec, err := o.dispatchTool(ctx, input.UserID, call.Name, call.Args)
			errText := ""
			if err != nil {
				log.Printf("Tool %s returned error: %v", call.Name, err)
				errText = err.Error()
				result = map[string]any{"error": errText}
			}
			if actionRec != nil {
				actionsTaken = append(actionsTaken, actionRec)
			}

			observation := sanitizeForGemini(result)
			if input.Debug {
				trace = append(trace, ToolTrace{
					Turn:   turn,
					Name:   call.Name,
					Args:   call.Args,
					Result: observation,
					Error:  errText,
					Ms:     time.Since(started).Milliseconds(),
				})
			}

			functionResponses = append(functionResponses, &genai.Part{
				FunctionResponse: &genai.FunctionResponse{
					ID:       call.ID,
					Name:     call.Name,
					Response: observation,
				},
			})
		}

		// Feed tool observations back to Gemini for the next reasoning step
		resp, err = chat.Send(ctx, functionResponses...)
		if err != nil {
			return nil, fmt.Errorf("gemini tool response failed: %w", err)
		}
	}

	if finalResponse == "" {
		finalResponse = "I've checked your data and updated your records. How else can I help your finances today? 🐾"
	}

	var toolsUsed []string
	for t := range toolsUsedSet {
		toolsUsed = append(toolsUsed, t)
	}

	// Persist conversation into MongoDB Atlas chat_messages collection.
	// Timed here rather than reusing the prompt's clock: the agent loop can run
	// for tens of seconds, and the transcript should record when the exchange
	// finished, not when it started.
	persistedAt := time.Now()
	_, _ = o.chatMessagesCol.InsertMany(ctx, []any{
		models.ChatMessage{
			ID:        bson.NewObjectID(),
			UserID:    input.UserID,
			Role:      "user",
			Content:   input.Message,
			CreatedAt: persistedAt,
		},
		models.ChatMessage{
			ID:        bson.NewObjectID(),
			UserID:    input.UserID,
			Role:      "model",
			Content:   finalResponse,
			ToolCalls: toolsUsed,
			Actions:   actionsTaken,
			// 10ms apart so the created_at sort always yields user-then-model.
			CreatedAt: persistedAt.Add(time.Millisecond * 10),
		},
	})

	return &AskCoachOutput{
		Response:     finalResponse,
		UserID:       input.UserID,
		ToolsUsed:    toolsUsed,
		ActionsTaken: actionsTaken,
		ToolTrace:    trace,
		Nudged:       nudged,
	}, nil
}

// dispatchTool dispatches a function call to the appropriate agent
func (o *Orchestrator) dispatchTool(ctx context.Context, userID, toolName string, args map[string]any) (map[string]any, map[string]any, error) {
	switch toolName {
	// ── FinancialRetrievalAgent Tools ──
	case "get_budget_summary":
		month, _ := args["month"].(string)
		res, err := o.retrievalAgent.GetBudgetSummary(ctx, userID, month)
		return res, nil, err

	case "get_transactions":
		limit := 20
		if l, ok := args["limit"].(float64); ok && l > 0 {
			limit = int(l)
		}
		category, _ := args["category"].(string)
		merchant, _ := args["merchant"].(string)
		res, err := o.retrievalAgent.GetTransactions(ctx, userID, limit, category, merchant)
		return map[string]any{"transactions": res}, nil, err

	case "get_recent_conversations":
		// 20 messages ≈ 10 exchanges. At 5 the coach could not recall anything
		// beyond the last couple of turns.
		limit := 20
		if l, ok := args["limit"].(float64); ok && l > 0 {
			limit = int(l)
		}
		res, err := o.retrievalAgent.GetRecentConversations(ctx, userID, limit)
		return map[string]any{"conversations": res}, nil, err

	case "get_spending_insights":
		month, _ := args["month"].(string)
		res, err := o.retrievalAgent.GetSpendingInsights(ctx, userID, month)
		return res, nil, err

	case "get_subscriptions":
		daysAhead := 30
		if d, ok := args["days_ahead"].(float64); ok && d > 0 {
			daysAhead = int(d)
		}
		res, err := o.retrievalAgent.GetSubscriptions(ctx, userID, daysAhead)
		return res, nil, err

	// ── FinancialActionAgent Tools ──
	case "update_budget_limit":
		var limit int64
		if l, ok := args["budget_limit"].(float64); ok {
			limit = int64(l)
		}
		res, err := o.actionAgent.UpdateBudgetLimit(ctx, userID, limit)
		return res, res, err

	case "add_transaction":
		merchant, _ := args["merchant"].(string)
		var amount int64
		if a, ok := args["amount"].(float64); ok {
			amount = int64(a)
		}
		category, _ := args["category"].(string)
		dateStr, _ := args["date"].(string)
		res, err := o.actionAgent.AddTransaction(ctx, userID, merchant, amount, category, dateStr)
		return res, res, err

	// ── FinancialResearchAgent Tools ──
	case "web_search":
		query, _ := args["query"].(string)
		res, err := o.researchAgent.WebSearch(ctx, query)
		return res, nil, err

	default:
		return nil, nil, fmt.Errorf("unknown tool: %s", toolName)
	}
}

// getFunctionDeclarations defines the 8 agent tools
func (o *Orchestrator) getFunctionDeclarations() []*genai.FunctionDeclaration {
	return []*genai.FunctionDeclaration{
		// 1. web_search (FinancialResearchAgent)
		{
			Name:        "web_search",
			Description: "Search the web for financial facts, Thai interest rates, bank savings rates, inflation, tax allowances, or market news.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"query": {
						Type:        genai.TypeString,
						Description: "The search query (e.g. 'Bank of Thailand policy rate 2026', 'SSF RMF tax deduction rules Thailand').",
					},
				},
				Required: []string{"query"},
			},
		},

		// 2. update_budget_limit (FinancialActionAgent)
		{
			Name:        "update_budget_limit",
			Description: "Update the user's monthly budget limit in Thai Baht.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"budget_limit": {
						Type:        genai.TypeNumber,
						Description: "The new monthly budget limit in Baht (e.g. 20000).",
					},
				},
				Required: []string{"budget_limit"},
			},
		},

		// 3. add_transaction (FinancialActionAgent)
		{
			Name:        "add_transaction",
			Description: "Record a new expense in the user's records. SmartFin tracks spending only, so income cannot be recorded.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"merchant": {
						Type:        genai.TypeString,
						Description: "Name of the merchant (e.g. 'Starbucks', '7-Eleven').",
					},
					"amount": {
						Type:        genai.TypeNumber,
						Description: "Transaction amount in Baht.",
					},
					"category": {
						Type:        genai.TypeString,
						Description: "Category (e.g. 'Food', 'Transport', 'Shopping', 'Bills').",
					},
					"date": {
						Type:        genai.TypeString,
						Description: "Date of transaction in YYYY-MM-DD format (optional, defaults to today).",
					},
				},
				Required: []string{"merchant", "amount"},
			},
		},

		// 4. get_budget_summary (FinancialRetrievalAgent)
		{
			Name:        "get_budget_summary",
			Description: "Retrieve the user's spending for a month: total expenses, the monthly budget limit and how much of it is used, and the spending breakdown by category.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"month": {
						Type:        genai.TypeString,
						Description: "Month in 'YYYY-MM' format (e.g. '2026-04') or 'current'. Defaults to current month if omitted.",
					},
				},
			},
		},

		// 5. get_transactions (FinancialRetrievalAgent)
		{
			Name:        "get_transactions",
			Description: "Retrieve the user's expenses, newest first, with optional filtering by merchant or category. Use the merchant filter for questions about a specific shop, service or payee (e.g. 'how much have I spent at Netflix'), then add up the amounts.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"limit": {
						Type:        genai.TypeInteger,
						Description: "Maximum number of transactions to return (default 20, max 100).",
					},
					"merchant": {
						Type:        genai.TypeString,
						Description: "Optional merchant name or part of it, case-insensitive (e.g. 'Netflix', 'Siam Paragon', 'Bumrungrad').",
					},
					"category": {
						Type:        genai.TypeString,
						Description: "Optional category filter. Categories are exactly: Food, Transport, Shopping, Bills, Groceries, Health, Entertainment, Gifts, Other. Leave it empty when unsure.",
					},
				},
			},
		},

		// 6. get_recent_conversations (FinancialRetrievalAgent)
		{
			Name:        "get_recent_conversations",
			Description: "Retrieve past chat conversations for context on prior user requests and recommendations.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"limit": {
						Type:        genai.TypeInteger,
						Description: "Number of past messages to fetch (default 20, max 20).",
					},
				},
			},
		},

		// 7. get_spending_insights (FinancialRetrievalAgent)
		{
			Name:        "get_spending_insights",
			Description: "Find spending worth reviewing in a month: unusually large purchases compared with the user's own history, small purchases at one merchant that add up, categories well above their recent average, the share spent on non-essentials, and overlapping subscriptions. Each item has a reason with figures. Use for 'what are my bad expenses', 'where am I wasting money', 'what should I cut back on', 'where can I save' or 'any unnecessary spending'.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"month": {
						Type:        genai.TypeString,
						Description: "Month in 'YYYY-MM' format (e.g. '2026-04') or 'current'. Defaults to the current month; if it has no expenses yet, the latest month that does is used and the result says so.",
					},
				},
			},
		},

		// 8. get_subscriptions (FinancialRetrievalAgent)
		{
			Name:        "get_subscriptions",
			Description: "Retrieve the user's tracked recurring subscriptions and bills (e.g. Netflix, phone plan, rent): amounts, billing cycle, next due dates, which are overdue, and the monthly-equivalent total. Use for 'what bills are due', 'upcoming payments' or 'how much do I spend on subscriptions'. Read-only.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"days_ahead": {
						Type:        genai.TypeInteger,
						Description: "Only list active bills due within this many days from today; overdue bills are always included. Default 30.",
					},
				},
			},
		},
	}
}

// sanitizeForGemini recursively normalizes map types into map[string]any and []any for protobuf
func sanitizeForGemini(data map[string]any) map[string]any {
	if data == nil {
		return map[string]any{}
	}
	b, err := json.Marshal(data)
	if err != nil {
		return data
	}
	var out map[string]any
	if err := json.Unmarshal(b, &out); err != nil {
		return data
	}
	return out
}

// describeProfile renders the user's profile for the system prompt, saying "not
// set" wherever a value is missing rather than inventing one.
//
// A user without a profile document used to be described as earning ฿30,000
// with a ฿15,000 budget, and the coach advised them on those invented figures.
// A zero budget is likewise "not set" rather than ฿0, which reads as a real limit
// the user has already blown. There is no income or savings goal to describe:
// SmartFin tracks spending only.
func describeProfile(u models.User, found bool) string {
	if !found {
		return "Current User Profile: not set up yet. Do not assume a budget. " +
			"If a question depends on one, say it has not been set and suggest adding it in Profile."
	}
	text := func(v string) string {
		if strings.TrimSpace(v) == "" {
			return "not set"
		}
		return v
	}
	budget := "not set"
	if u.BudgetLimit > 0 {
		budget = fmt.Sprintf("฿%d", u.BudgetLimit)
	}
	return fmt.Sprintf(
		"Current User Profile:\n- Name: %s\n- Monthly Budget Limit: %s\n- Financial Goal: %s",
		text(u.Name), budget, text(u.FinancialHealth),
	)
}
