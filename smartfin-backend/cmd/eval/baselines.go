package main

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"github.com/google/generative-ai-go/genai"
)

const (
	modelName   = "gemini-2.5-flash"
	temperature = 0.5
)

// The persona and answer guidelines are copied from the coach's system prompt
// (internal/agents/orchestrator.go) with the tool-orchestration steps removed, so
// the three systems differ only in how they get the user's data.
const personaHead = `You are Kwak, SmartFin's AI Coach — a friendly, highly intelligent AI financial coach for a Thai user. Your name comes from แมวกวัก, the Thai beckoning lucky cat.
Use your name only when introducing yourself or when asked who you are, and call yourself the AI Coach otherwise; do not sign or open every reply with it.
You speak in a warm, encouraging tone and occasionally use the paw print emoji 🐾.`

const answerGuidelines = `Answer guidelines:
- Format amounts in Thai Baht (฿) with no decimals.
- All dates are Thai local time (UTC+07:00). Use the current date above when resolving "today", "this month" or "last week" — never guess it.
- Keep answers concise (3-4 sentences) unless user asks for detailed analysis.
- SmartFin tracks spending only: expenses and the monthly budget. It records no income and no savings goals, so never state what the user earned or saved. If asked, say the app tracks spending and budget, and answer with those instead.
- Subscriptions and bills are tracked by the user in the app. If the user says they paid a bill, tell them to tap "Mark paid" in Subscriptions & Bills.
- Gently redirect non-financial topics back to financial health.`

func dateLine(now time.Time) string {
	n := now.In(summaries.Zone)
	return fmt.Sprintf("Current date and time: %s (Thailand, UTC+07:00)\nCurrent month: %s",
		n.Format("Monday, 2 January 2006, 15:04"), summaries.StringOf(n))
}

// NoRetrievalPrompt gives the model the persona and the date, and nothing about the user.
func NoRetrievalPrompt(now time.Time) string {
	return personaHead + "\n\n" + dateLine(now) + "\n\n" + answerGuidelines
}

// OneShotPrompt pastes the user's complete records into the prompt: profile,
// per-month summaries, every transaction and every bill. It is a deliberately
// strong baseline — more context than the agent ever retrieves in one call.
func OneShotPrompt(d UserData, t Truth, now time.Time) string {
	var b strings.Builder
	b.WriteString(personaHead + "\n\n" + dateLine(now) + "\n\n")
	fmt.Fprintf(&b, "Current User Profile:\n- Name: %s\n- Monthly Budget Limit: %s\n\n",
		d.Name, baht(d.Budget))
	b.WriteString("The user's complete spending records follow. Answer questions about their money only from these records.\n\n")

	b.WriteString("MONTHLY SPENDING\n")
	if len(t.Months) == 0 {
		b.WriteString("- No months with records.\n")
	}
	for i := len(t.Months) - 1; i >= 0; i-- {
		m := t.Months[i]
		e := t.MonthExpense[m]
		label := m
		if p, err := time.Parse("2006-01", m); err == nil {
			label = fmt.Sprintf("%s (%s)", m, p.Format("January 2006"))
		}
		pct := 0.0
		if t.Budget > 0 {
			pct = float64(e) / float64(t.Budget) * 100
		}
		fmt.Fprintf(&b, "- %s: expenses %s, budget used %.1f%%. Categories: %s\n",
			label, baht(e), pct, categoryList(t.CatMonth[m]))
	}

	b.WriteString("\nEXPENSES (newest first)\n")
	if len(d.Txs) == 0 {
		b.WriteString("- No transactions recorded.\n")
	}
	txs := append([]TxRow(nil), d.Txs...)
	sort.Slice(txs, func(i, j int) bool { return txs[i].Date.After(txs[j].Date) })
	for _, tx := range txs {
		day := tx.Date.In(summaries.Zone)
		fmt.Fprintf(&b, "- %s (%s) | %s | %s | %s | %s\n",
			day.Format("2006-01-02"), day.Format("2 Jan 2006"), tx.Merchant, tx.Type, tx.Category, baht(tx.Amount))
	}

	b.WriteString("\nBILLS & SUBSCRIPTIONS (active)\n")
	if len(d.Bills) == 0 {
		b.WriteString("- No bills tracked.\n")
	}
	for _, bill := range d.Bills {
		fmt.Fprintf(&b, "- %s | %s %s | %s | due %s (%s)\n",
			bill.Name, baht(bill.Amount), bill.Cycle, bill.Category, bill.DueDate, dueText(bill.Days))
	}
	if len(d.Bills) > 0 {
		fmt.Fprintf(&b, "Monthly total of active bills: %s\n", baht(t.BillsMonthly))
	}

	b.WriteString("\n" + answerGuidelines)
	return b.String()
}

// askGemini sends one question to a plain chat with the given system prompt,
// replaying history the same way the orchestrator does.
func askGemini(ctx context.Context, client *genai.Client, system string, history []Turn, question string) (string, error) {
	model := client.GenerativeModel(modelName)
	model.SetTemperature(temperature)
	model.SystemInstruction = genai.NewUserContent(genai.Text(system))
	chat := model.StartChat()
	for _, h := range history {
		if h.Role == "user" || h.Role == "model" {
			chat.History = append(chat.History, &genai.Content{Role: h.Role, Parts: []genai.Part{genai.Text(h.Content)}})
		}
	}
	resp, err := chat.SendMessage(ctx, genai.Text(question))
	if err != nil {
		return "", err
	}
	var parts []string
	if len(resp.Candidates) > 0 && resp.Candidates[0].Content != nil {
		for _, p := range resp.Candidates[0].Content.Parts {
			if text, ok := p.(genai.Text); ok {
				parts = append(parts, string(text))
			}
		}
	}
	return strings.Join(parts, " "), nil
}

func categoryList(m map[string]int64) string {
	type kv struct {
		k string
		v int64
	}
	var rows []kv
	for k, v := range m {
		rows = append(rows, kv{k, v})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].v != rows[j].v {
			return rows[i].v > rows[j].v
		}
		return rows[i].k < rows[j].k
	})
	parts := make([]string, 0, len(rows))
	for _, r := range rows {
		parts = append(parts, r.k+" "+baht(r.v))
	}
	if len(parts) == 0 {
		return "none"
	}
	return strings.Join(parts, ", ")
}

func dueText(days int) string {
	switch {
	case days < 0:
		return fmt.Sprintf("%d days overdue", -days)
	case days == 0:
		return "due today"
	case days == 1:
		return "due tomorrow"
	}
	return fmt.Sprintf("due in %d days", days)
}

func baht(v int64) string {
	s := fmt.Sprintf("%d", abs64(v))
	var out []byte
	for i := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			out = append(out, ',')
		}
		out = append(out, s[i])
	}
	if v < 0 {
		return "-฿" + string(out)
	}
	return "฿" + string(out)
}

func signedBaht(v int64) string { return baht(v) }
