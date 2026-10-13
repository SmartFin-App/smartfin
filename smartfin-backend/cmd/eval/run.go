package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sort"
	"strings"
	"time"

	"google.golang.org/genai"
)

// Trial is one answer from one system to one case.
type Trial struct {
	CaseID       string           `json:"case"`
	Category     string           `json:"category"`
	Scope        string           `json:"scope"`
	System       string           `json:"system"`
	Repeat       int              `json:"repeat"`
	UID          string           `json:"uid,omitempty"`
	Question     string           `json:"question"`
	Answer       string           `json:"answer"`
	LatencyMs    int64            `json:"latency_ms"`
	Status       string           `json:"status"` // ok | error | timeout
	Error        string           `json:"error,omitempty"`
	Retries      int              `json:"retries"`
	Nudged       bool             `json:"nudged,omitempty"`
	Tools        []string         `json:"tools,omitempty"`
	ToolTrace    []TraceEntry     `json:"tool_trace,omitempty"`
	ActionsTaken []map[string]any `json:"actions_taken,omitempty"`
	DBBefore     *Snapshot        `json:"db_before,omitempty"`
	DBAfter      *Snapshot        `json:"db_after,omitempty"`
	Score        Score            `json:"score"`
}

// Runner answers cases with each system.
type Runner struct {
	api     *Client
	gemini  *genai.Client
	prefix  string
	timeout time.Duration
	prompts map[string]string // "<system>|seeded" or "<system>|empty"
}

var backoffs = []time.Duration{5 * time.Second, 15 * time.Second, 30 * time.Second}

func (r *Runner) uidFor(c Case, rep int) string {
	return fmt.Sprintf("%s%s-r%d", r.prefix, strings.ToLower(c.ID), rep)
}

func (r *Runner) runTrial(ctx context.Context, system string, c Case, rep int) *Trial {
	t := &Trial{CaseID: c.ID, Category: c.Category, Scope: c.Scope, System: system, Repeat: rep, Question: c.Question}
	if system == "agentic" {
		r.runAgentic(ctx, c, rep, t)
	} else {
		r.runBaseline(ctx, system, c, t)
	}
	return t
}

func (r *Runner) runAgentic(ctx context.Context, c Case, rep int, t *Trial) {
	uid := r.uidFor(c, rep)
	t.UID = uid

	for _, prior := range c.PriorTurns {
		pctx, cancel := context.WithTimeout(ctx, r.timeout)
		res, code, err := r.api.Ask(pctx, uid, prior, nil)
		cancel()
		if err != nil || code != 200 {
			t.Status, t.Error = "error", "earlier turn failed: "+describe(code, err, res)
			return
		}
	}

	before, err := TakeSnapshot(ctx, uid)
	if err != nil {
		t.Error = "snapshot before: " + err.Error()
	}
	t.DBBefore = before

	for attempt := 0; ; attempt++ {
		actx, cancel := context.WithTimeout(ctx, r.timeout)
		start := time.Now()
		res, code, err := r.api.Ask(actx, uid, c.Question, c.History)
		t.LatencyMs = time.Since(start).Milliseconds()
		cancel()

		if err == nil && code == 200 {
			t.Status = "ok"
			t.Answer = res.Response
			t.ToolTrace = res.ToolTrace
			t.Nudged = res.Nudged
			t.ActionsTaken = res.ActionsTaken
			t.Tools = toolNames(res)
			break
		}
		msg := describe(code, err, res)
		if isRateLimited(msg) && attempt < len(backoffs) {
			// Retry only if the failed attempt wrote nothing, so a retry can never
			// double an action.
			now, serr := TakeSnapshot(ctx, uid)
			if serr == nil && before != nil && before.Same(now) {
				t.Retries++
				time.Sleep(backoffs[attempt] + time.Duration(rand.Intn(2000))*time.Millisecond)
				continue
			}
		}
		t.Status, t.Error = "error", msg
		if isTimeout(err, msg) {
			t.Status = "timeout"
		}
		break
	}

	after, err := TakeSnapshot(ctx, uid)
	if err != nil {
		t.Error = strings.TrimSpace(t.Error + " snapshot after: " + err.Error())
	}
	t.DBAfter = after
}

func (r *Runner) runBaseline(ctx context.Context, system string, c Case, t *Trial) {
	data := "seeded"
	if c.NoData {
		data = "empty"
	}
	prompt := r.prompts[system+"|"+data]
	for attempt := 0; ; attempt++ {
		actx, cancel := context.WithTimeout(ctx, r.timeout)
		start := time.Now()
		answer, err := askGemini(actx, r.gemini, prompt, c.History, c.Question)
		t.LatencyMs = time.Since(start).Milliseconds()
		cancel()
		if err == nil {
			t.Status, t.Answer = "ok", answer
			return
		}
		msg := err.Error()
		if isRateLimited(msg) && attempt < len(backoffs) {
			t.Retries++
			time.Sleep(backoffs[attempt] + time.Duration(rand.Intn(2000))*time.Millisecond)
			continue
		}
		t.Status, t.Error = "error", msg
		if isTimeout(err, msg) {
			t.Status = "timeout"
		}
		return
	}
}

// toolNames returns the tools in the order they were called when the trace is
// available, otherwise the (unordered) tools_used list.
func toolNames(res AskResult) []string {
	var out []string
	seen := map[string]bool{}
	for _, e := range res.ToolTrace {
		if !seen[e.Name] {
			seen[e.Name] = true
			out = append(out, e.Name)
		}
	}
	if len(out) > 0 {
		return out
	}
	out = append(out, res.ToolsUsed...)
	sort.Strings(out)
	return out
}

func describe(code int, err error, res AskResult) string {
	if err != nil {
		return err.Error()
	}
	return strings.TrimSpace(fmt.Sprintf("HTTP %d %s %s", code, res.Error, res.Details))
}

func isRateLimited(msg string) bool {
	m := strings.ToLower(msg)
	return strings.Contains(m, "429") || strings.Contains(m, "resource_exhausted") || strings.Contains(m, "quota") || strings.Contains(m, "rate limit")
}

func isTimeout(err error, msg string) bool {
	if err != nil && errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	m := strings.ToLower(msg)
	return strings.Contains(m, "deadline exceeded") || strings.Contains(m, "client.timeout") || strings.Contains(m, "timeout")
}
