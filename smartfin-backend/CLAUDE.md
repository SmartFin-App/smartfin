# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Backend for SmartFin, a personal finance copilot for Thai users. See the root `../CLAUDE.md` for the monorepo picture and the Flutter client it serves.

## Commands

Go 1.26, module `github.com/SmartFin-App/smartfin-backend`. Run all of these from `smartfin-backend/`.

```bash
go run cmd/main.go                        # serve on $PORT (default 3000)
go build ./...
go vet ./...
go test ./...
go test ./internal/agents -run TestFunctionDeclarations -v   # single test
```

`.env` is loaded by godotenv at startup; a missing `MONGODB_URI` or `DB_NAME` is a `log.Fatal`. Variables: `MONGODB_URI`, `DB_NAME`, `PORT`, `GEMINI_API_KEY`, optional `SERPAPI_API_KEY`.

Two tests exist, both in `internal/agents/agent_test.go`. `TestResearchAgentWebSearchFallback` makes a **real outbound web request** with an 8s timeout, so it is slow and fails offline.

## Stack details that are easy to guess wrong

- **Fiber v2** (`*fiber.Ctx`), not Gin or net/http — the root README misstates this.
- **`mongo-driver/v2`**: IDs are `bson.ObjectID` (not `primitive.ObjectID`), and `mongo.Connect` takes options only, with no context argument.
- Gemini via `google/generative-ai-go`; the model everywhere is `gemini-2.5-flash`.
- Money is **integer Thai Baht** — `int64` throughout, formatted with `฿` and comma separators, never a float and never decimals.

## Structure

`cmd/main.go` → `internal/routes/routes.go` → `internal/handlers/` → `internal/agents/`.

`config/database.go` exposes package globals `config.DB` and `config.GetCollection(name)`; handlers reach for collections directly, so there is no repository or service layer to thread changes through. Collections: `users`, `transactions`, `monthly_summaries`, `chat_messages`.

`internal/summaries` is the one shared piece of domain logic: it owns the month-window rules and cache invalidation used by both the handlers and the agents. **Never compute a month boundary inline** — call `summaries.Bounds` / `summaries.StringOf`. Windows are anchored to a fixed +07:00 (`summaries.Zone`), not UTC, so a 06:00 Bangkok expense on the 1st is filed under the right month. Any write that touches a transaction must call `summaries.Invalidate`/`InvalidateFor`, including for frozen months — a backdated entry is exactly the case that otherwise stays invisible to every total.

**Users are keyed by Firebase UID** (`firebase_uid` string), not by Mongo `_id` — every user-scoped query filters on that string. The backend does **not** verify Firebase tokens; the UID arrives as a plain path param or body field, so the API is effectively unauthenticated today.

The single-transaction routes (`GET /api/transactions/detail/:id`, `PUT`, `DELETE`) additionally require a `user_id` (query string or body) and filter on it via `ownerFromRequest` — without that they had no notion of an owner at all, so a guessed ObjectID reached another user's record. That helper is the one place to swap for a verified token.

`routes.go` also holds the admin endpoints inline (see below), which is why that file is much longer than the route list suggests.

## The coach is an agentic loop, not one-shot RAG

`internal/agents/orchestrator.go` backs `POST /api/coach/ask` (45s handler timeout). It builds a system prompt grounded in the user's profile, declares **7 tools**, then runs a **max-5-iteration** Gemini function-calling loop, dispatching through `dispatchTool` to three sub-agents:

| Agent | Tools |
| --- | --- |
| `retrieval_agent.go` | `get_budget_summary`, `get_transactions`, `get_recent_conversations` |
| `action_agent.go` | `set_savings_goal`, `update_budget_limit`, `add_transaction` — these **write** to Mongo and are echoed back to the client as `actions_taken` |
| `research_agent.go` | `web_search` — SerpAPI if `SERPAPI_API_KEY` is set, else scrapes DuckDuckGo HTML, else a hardcoded Thai-finance fallback blurb |

When working on this loop:

- Tool results must pass through `sanitizeForGemini` (a JSON round-trip) before being returned as a `genai.FunctionResponse`, or protobuf conversion fails on types that aren't plain `map[string]any` / `[]any`.
- Adding or removing a tool means updating `agent_test.go`, which asserts **exactly 7** declarations and checks each by name.
- Gemini arguments arrive as `float64` regardless of declared schema type, hence the `args["amount"].(float64)` conversions in `dispatchTool`.
- If the loop exhausts its iterations without producing text, the orchestrator returns a canned "I've checked your data and updated your records" reply rather than an error.
- Every exchange is persisted to `chat_messages` with the tool names used — that is what `get_recent_conversations` later reads back.
- A `detect_spending_anomalies` tool and an external ML-service integration were both deliberately removed (commits `12827ac`, `53f79be`). Don't reintroduce either without asking.

Nothing automatically checks the coach's answer quality — the `evaluate_rag.py` harness that used to do this was removed — so prompt and tool changes need manual verification against a seeded local backend.

## Scanning is stateless; the client persists

`scanner_handler.go` (`POST /api/scanner/process`) takes multipart `image` + `user_id`, calls Gemini Vision at temperature 0 with a prompt demanding bare JSON, strips ```` ```json ```` fences before unmarshalling, and returns `{merchant, amount, date, confidence, raw_text}`. On a parse failure it returns `Unknown Merchant` / 0 / today rather than erroring, so the user can still correct it downstream.

The extraction prompt is explicit about **Thai script transliteration and Buddhist-era years** (2567/2569 → Gregorian) because the inputs are Thai mobile-banking e-slips (PromptPay, K PLUS, SCB EASY, Krungthai NEXT, BBL). Keep both requirements if you rewrite it.

This handler writes **nothing** to Mongo — the Flutter app creates the transaction separately after the user confirms on the verify screen.

## Two different "summary" endpoints

- `GET /api/summary/:user_id` (`summary_handler.go`) returns a cached `MonthlySummary` document per `YYYY-MM`, combining **recurring income from the user profile** with one-time income transactions. `is_frozen` is derived from whether the month's window has fully elapsed (never from comparing month strings against the server clock, which let a client an hour ahead freeze a live month at zero). Frozen months are served from cache; the current month is recalculated on read and written back with `ReplaceOne` — a `$set` carrying `_id` is rejected as an immutable-field update and silently left the cache stale.
- `GET /api/transactions/summary/:user_id` (`transaction_handler.go`) is a separate ad-hoc aggregation over transactions only, with no profile income and no caching.

They are not interchangeable — check which one a caller actually needs.

## Admin endpoints are unprotected and destructive

Registered outside the `/api` group in `routes.go`:

- `POST /admin/seed-transactions?user_id=…` — inserts ~45 hardcoded Nov 2025–Apr 2026 Thai transactions. This is what makes the coach and the dashboard charts demoable.
- `DELETE /admin/reset-summaries`, `DELETE /admin/reset-transactions` — wipe data. Never call these without an explicit instruction.
