package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client talks to a running SmartFin API. The agentic system is evaluated
// through the real HTTP endpoint, exactly as the app calls it.
type Client struct {
	Base string
	http *http.Client
}

func NewClient(base string, timeout time.Duration) *Client {
	return &Client{Base: strings.TrimRight(base, "/"), http: &http.Client{Timeout: timeout}}
}

// TraceEntry mirrors agents.ToolTrace as it arrives over JSON.
type TraceEntry struct {
	Turn   int            `json:"turn"`
	Name   string         `json:"name"`
	Args   map[string]any `json:"args"`
	Result map[string]any `json:"result,omitempty"`
	Error  string         `json:"error,omitempty"`
	Ms     int64          `json:"ms"`
}

// AskResult is the coach endpoint's response, success or error.
type AskResult struct {
	Response     string           `json:"response"`
	ToolsUsed    []string         `json:"tools_used"`
	ActionsTaken []map[string]any `json:"actions_taken"`
	ToolTrace    []TraceEntry     `json:"tool_trace"`
	Nudged       bool             `json:"nudged"`
	Error        string           `json:"error"`
	Details      string           `json:"details"`
}

func (c *Client) send(ctx context.Context, method, path string, body any) (int, []byte, error) {
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return 0, nil, err
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.Base+path, reader)
	if err != nil {
		return 0, nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	return resp.StatusCode, data, err
}

func (c *Client) expectOK(ctx context.Context, method, path string, body any) error {
	code, data, err := c.send(ctx, method, path, body)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	if code < 200 || code > 299 {
		return fmt.Errorf("%s %s: HTTP %d: %s", method, path, code, truncate(string(data), 200))
	}
	return nil
}

func (c *Client) Health(ctx context.Context) error {
	return c.expectOK(ctx, http.MethodGet, "/health", nil)
}

func (c *Client) CreateUser(ctx context.Context, uid string, budget int64) error {
	return c.expectOK(ctx, http.MethodPost, "/api/users", map[string]any{
		"firebase_uid": uid,
		"name":         "Eval User",
		"email":        uid + "@example.com",
		"budget_limit": budget,
	})
}

func (c *Client) Seed(ctx context.Context, uid string) error {
	return c.expectOK(ctx, http.MethodPost, "/admin/seed-transactions?user_id="+url.QueryEscape(uid), nil)
}

func (c *Client) CreateBill(ctx context.Context, uid, name string, amount int64, category, dueDate string) error {
	return c.expectOK(ctx, http.MethodPost, "/api/subscriptions", map[string]any{
		"user_id":       uid,
		"name":          name,
		"amount":        amount,
		"billing_cycle": "monthly",
		"next_due_date": dueDate,
		"category":      category,
	})
}

// Ask calls the coach with the debug trace requested.
func (c *Client) Ask(ctx context.Context, uid, message string, history []Turn) (AskResult, int, error) {
	hist := make([]Turn, 0, len(history))
	hist = append(hist, history...)
	code, data, err := c.send(ctx, http.MethodPost, "/api/coach/ask", map[string]any{
		"user_id": uid,
		"message": message,
		"history": hist,
		"debug":   true,
	})
	var r AskResult
	if err != nil {
		return r, code, err
	}
	if jerr := json.Unmarshal(data, &r); jerr != nil {
		return r, code, fmt.Errorf("decode coach response (HTTP %d): %v: %s", code, jerr, truncate(string(data), 200))
	}
	return r, code, nil
}

// DeleteUser erases an eval user through the API's own account deletion. It
// refuses anything that is not an eval user, so a bug here can never reach a
// real account in the shared database.
func (c *Client) DeleteUser(ctx context.Context, uid, prefix string) error {
	if !strings.HasPrefix(uid, "eval-") || !strings.HasPrefix(uid, prefix) {
		return fmt.Errorf("refusing to delete %q: not an eval user", uid)
	}
	return c.expectOK(ctx, http.MethodDelete, "/api/users/"+url.PathEscape(uid), nil)
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
