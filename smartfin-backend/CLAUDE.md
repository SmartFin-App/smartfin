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
go test ./cmd/eval                        # evaluation scoring rules (offline)
```

`.env` is loaded by godotenv at startup; a missing `MONGODB_URI` or `DB_NAME` is a `log.Fatal`. Variables: `MONGODB_URI`, `DB_NAME`, `PORT`, `GEMINI_API_KEY`, optional `SERPAPI_API_KEY`.

Tests live in `internal/agents`, `internal/models` and `internal/summaries` (the date and projection rules are pure functions tested against a fixed clock). `TestResearchAgentWebSearchFallback` in `agent_test.go` makes a **real outbound web request** with an 8s timeout, so it is slow and fails offline — `go test ./internal/summaries ./internal/models` is the fast offline set.

## Stack details that are easy to guess wrong

- **Fiber v2** (`*fiber.Ctx`), not Gin or net/http — the root README misstates this.
- **`mongo-driver/v2`**: IDs are `bson.ObjectID` (not `primitive.ObjectID`), and `mongo.Connect` takes options only, with no context argument.
- Gemini via `google/generative-ai-go`; the model everywhere is `gemini-2.5-flash`.
- Money is **integer Thai Baht** — `int64` throughout, formatted with `฿` and comma separators, never a float and never decimals.

## Structure

`cmd/main.go` → `internal/routes/routes.go` → `internal/handlers/` → `internal/agents/`.

`config/database.go` exposes package globals `config.DB` and `config.GetCollection(name)`; handlers reach for collections directly, so there is no repository or service layer to thread changes through. Collections: `users`, `transactions`, `monthly_summaries`, `chat_messages`, `subscriptions`.

**Every index the app relies on is declared in `config/indexes.go`** and created at startup by `EnsureIndexes` (idempotent, and non-fatal — a missing index costs speed, not correctness). Keys are ordered equality-then-sort (`{user_id, date: -1}`, `{user_id, created_at: -1}`), which is what lets one index serve both the filter and the sort. **If you add a user-scoped query, add its index there**, or it becomes a collection scan.

`internal/summaries` is the one shared piece of domain logic: it owns the month-window rules and cache invalidation used by both the handlers and the agents. **Never compute a month boundary inline** — call `summaries.Bounds` / `summaries.StringOf`. Windows are anchored to a fixed +07:00 (`summaries.Zone`), not UTC, so a 06:00 Bangkok expense on the 1st is filed under the right month. Any write that touches a transaction must call `summaries.Invalidate`/`InvalidateFor`, including for frozen months — a backdated entry is exactly the case that otherwise stays invisible to every total.

**Users are keyed by Firebase UID** (`firebase_uid` string), not by Mongo `_id` — every user-scoped query filters on that string. The backend does **not** verify Firebase tokens; the UID arrives as a plain path param or body field, so the API is effectively unauthenticated today.

The single-transaction routes (`GET /api/transactions/detail/:id`, `PUT`, `DELETE`) additionally require a `user_id` (query string or body) and filter on it via `ownerFromRequest` — without that they had no notion of an owner at all, so a guessed ObjectID reached another user's record. That helper is the one place to swap for a verified token.

`routes.go` also holds the admin endpoints inline (see below), which is why that file is much longer than the route list suggests.

## The coach is an agentic loop, not one-shot RAG

`internal/agents/orchestrator.go` backs `POST /api/coach/ask` (45s handler timeout). It builds a system prompt grounded in the user's profile, declares **8 tools**, then runs a **max-5-iteration** Gemini function-calling loop, dispatching through `dispatchTool` to three sub-agents:

| Agent | Tools |
| --- | --- |
| `retrieval_agent.go` | `get_budget_summary`, `get_transactions`, `get_subscriptions`, `get_recent_conversations` |
| `action_agent.go` | `set_savings_goal`, `update_budget_limit`, `add_transaction` — these **write** to Mongo and are echoed back to the client as `actions_taken` |
| `research_agent.go` | `web_search` — SerpAPI if `SERPAPI_API_KEY` is set, else scrapes DuckDuckGo HTML, else a hardcoded Thai-finance fallback blurb |

When working on this loop:

- Tool results must pass through `sanitizeForGemini` (a JSON round-trip) before being returned as a `genai.FunctionResponse`, or protobuf conversion fails on types that aren't plain `map[string]any` / `[]any`.
- Adding or removing a tool means updating `agent_test.go`, which asserts **exactly 8** declarations and checks each by name.
- `get_transactions` has **no date filter** and returns the newest rows (default 20; a limit above 100 silently becomes 30). Questions about one shop or service must use its optional `merchant` filter (case-insensitive fragment) — before it existed, the coach could not answer "how much have I spent at Netflix?" and the evaluation traced 7 of 13 failures to it. The category filter is an escaped, case-insensitive prefix; the declaration lists the real category names because the model otherwise invents ones like "Healthcare".
- `get_subscriptions` is deliberately **read-only**. The system prompt tells the model to send a user who says "I paid my Netflix" to the app's Mark paid button instead of calling `add_transaction` — that would log the expense but leave the bill's due date where it was.
- Gemini arguments arrive as `float64` regardless of declared schema type, hence the `args["amount"].(float64)` conversions in `dispatchTool`.
- If the loop exhausts its iterations without producing text, the orchestrator returns a canned "I've checked your data and updated your records" reply rather than an error.
- **A first reply that only promises to check is nudged once.** Gemini sometimes answers "give me a moment to look that up" without calling a tool, and a reply without a tool call used to end the loop — the user got the promise and nothing else. `looksLikeStall` (short text with phrases like "let me check", "สักครู่", "ขอตรวจสอบ") triggers one follow-up asking the model to call the tool now. In the evaluation this took the coach's shared pass rate from 84% to 99%. Keep the phrase list conservative: a real answer that happens to match gets an unnecessary extra model call, not a wrong answer. The coach can still *claim* an action without calling the write tool — that is not fixed.
- Every exchange is persisted to `chat_messages` with the tool names used — that is what `get_recent_conversations` later reads back.
- **Everything the model sees is Thai local time.** `get_recent_conversations` and `get_transactions` format through `summaries.Zone` (+07:00) — MongoDB hands back UTC, and passing that through unconverted put chat memory on the wrong *day*. The system prompt also carries the current date and month, because the model has no clock of its own and was otherwise inferring "today" from training data.
- `get_recent_conversations` defaults to 20 messages. Note the guard in `retrieval_agent.go`: anything **above** 20 silently collapses to 6, so raising the default past the cap returns *fewer* messages, not more.
- A `detect_spending_anomalies` tool and an external ML-service integration were both deliberately removed (commits `12827ac`, `53f79be`). Don't reintroduce either without asking.

### Evaluating the coach (`cmd/eval`)

`cmd/eval` scores the coach against answers that can be checked. It creates throwaway `eval-<run>-*` users through the API (profile, the 47 seeded transactions, three bills dated relative to the run day), asks 30 scripted questions (`cmd/eval/cases.go`), and scores every answer **by rule against figures recomputed from MongoDB** — no LLM judge. The same questions go to two baselines on the same model and temperature: no retrieval, and one-shot RAG with the user's complete records pasted into the prompt.

```bash
PORT=3001 COACH_EVAL_TRACE=1 go run cmd/main.go     # terminal 1: trace-enabled server
go run ./cmd/eval -repeats 3                         # terminal 2: ~270 answers, ~15 min
go run ./cmd/eval -rescore eval-results/<run>        # re-score saved answers after a rule change
go run ./cmd/eval -cleanup                           # remove eval users left by an interrupted run
```

- **Tool trace.** `POST /api/coach/ask` returns `tool_trace` (each call's args, result and timing) only when the request sends `"debug": true` **and** the server runs with `COACH_EVAL_TRACE=1`. The harness uses it for month coverage and to attribute a missing figure to retrieval (never fetched) or generation (fetched, then lost).
- **Scoring rules** live in `cmd/eval/score.go` with unit tests. When an audit finds a rule wrong, fix the rule and `-rescore` every system — never edit individual verdicts.
- **Isolation.** Each agentic trial gets its own user, because the coach writes `chat_messages` and some cases write the profile. Deletion goes through `DELETE /api/users/:uid` and refuses any uid without the `eval-` prefix; the admin reset routes are never used.
- Raw output (`eval-results/`, answers and traces) is gitignored; copy `summary.md` to `smartfin-docs/eval/` to keep a run.

## Scanning is stateless; the client persists

`scanner_handler.go` (`POST /api/scanner/process`) takes multipart `image` + `user_id`, calls Gemini Vision at temperature 0 with a prompt demanding bare JSON, strips ```` ```json ```` fences before unmarshalling, and returns `{merchant, amount, date, confidence, raw_text}`. On a parse failure it returns `Unknown Merchant` / 0 / today rather than erroring, so the user can still correct it downstream.

The extraction prompt is explicit about **Thai script transliteration and Buddhist-era years** (2567/2569 → Gregorian) because the inputs are Thai mobile-banking e-slips (PromptPay, K PLUS, SCB EASY, Krungthai NEXT, BBL). Keep both requirements if you rewrite it.

This handler writes **nothing** to Mongo — the Flutter app creates the transaction separately after the user confirms on the verify screen.

Two fallbacks hide failures from callers, so check them when evaluating: an unparseable model reply returns `Unknown Merchant` / 0, and a missing date silently becomes **today** (server local time), which makes a receipt with no printed date look correctly dated.

### Evaluating the scanner (`cmd/slipeval`)

`go run ./cmd/slipeval -repeats 2` sends every image in `eval-slips/images/` to `/api/scanner/process` as the app does (original file, multipart) and compares merchant, amount and date with `eval-slips/labels.csv`. **`eval-slips/` is git-ignored and must stay that way** — real slips carry names, account numbers and reference IDs; `summary.md` deliberately reports only file names and right/wrong marks. Rules: amount within ±฿0.5 (the scanner returns whole baht), merchant = normalised name contains any `|`-separated alias (Thai names are transliterated, so exact matching is unfair), date exact, and a blank label date means "not printed" and is excluded. Scans are saved raw, so after correcting a label run `go run ./cmd/slipeval -rescore eval-slips/results/<run>` — no new Gemini calls. Labels marked unverified are flagged in the summary.

## Endpoints beyond the obvious CRUD

- `GET /api/coach/history/:user_id` — the stored transcript, newest-first internally then reversed so the client renders top-down. The orchestrator has always persisted both sides of every exchange; this is what reads it back. The Flutter coach screen is disposed on every tab switch, so the transcript **must** come from here rather than widget state.
- `GET /api/summary/:user_id/savings-goal` — progress toward the savings goal. "Saved" is *derived*: the sum of each **completed** month's savings, counted from whichever came first — account creation or the oldest transaction — and capped at 24 months. The live month is excluded and reported separately as `this_month_surplus`: its income lands on day one, and folding it in marked goals "reached" before the month had been lived through. There is deliberately no stored balance to drift from the transactions. The response also carries a **plan** from `summaries.ProjectGoal` (`internal/summaries/goal.go`, unit-tested): `planned_monthly_saving` (income − budget, floored at zero), `months_to_goal` (null when the budget saves nothing), and — only when `savings_target_date` parses as `YYYY-MM-DD` — `required_monthly_saving` and `on_track`. A free-text target (the coach can store "in 6 months") is left unparsed rather than guessed at.
- `DELETE /api/users/:firebase_uid` — erases the profile, transactions, summaries, chat messages and subscriptions. Owned records go first, so a partial failure leaves a recoverable account rather than orphaned data. Irreversible, and unauthenticated like everything else — the first handler to cover when token verification lands.
- `POST|GET|DELETE /api/users/:firebase_uid/photo` — avatars in a GridFS bucket, filename = the UID. **`photo_url` is stored as a relative path** (`/api/users/<uid>/photo`), never an absolute URL: the API host changes between emulator, LAN device and deployment, and a baked-in URL rots the moment it does.

`UpdateUser` binds to `models.UpdateUserRequest`, a typed partial with **pointer fields** — that is what keeps "absent" distinguishable from "set to zero", so clearing a savings goal is a real write rather than a no-op. It also keeps money as `int64` instead of a JSON `float64` that lands in Mongo as a double, and means an unknown key can no longer be `$set` into the document.

## Subscriptions & bills

`subscription_handler.go` serves a tracker of recurring bills the user enters by hand: `POST /api/subscriptions`, `GET /api/subscriptions/:user_id[?active=true]`, `PUT|DELETE /api/subscriptions/:id` (owner-scoped through `ownerFromRequest`, like single transactions) and `POST /api/subscriptions/:id/pay`. The date rules are pure functions in `internal/summaries/subscriptions.go`, unit-tested against a fixed clock.

- **A due date is a Thai calendar day**, stored as midnight +07:00 and parsed with `summaries.ParseDueDate` — never `parseTxDate`, which reads a date-only string as UTC midnight. Mongo hands the instant back as 17:00 UTC the day before, so the API also sends `due_date` (`"2026-09-14"`), `days_until_due`, `status` (`paused | overdue | due_today | due_soon | upcoming`) and `formatted_due_date`, and clients are expected to use those rather than converting `next_due_date` themselves. The list adds `monthly_total` (every active bill at its monthly equivalent), `overdue_count`, `due_soon_count` and `due_soon_total`.
- **`anchor_day` keeps month-end bills on their day.** `time.AddDate` turns Jan 31 + 1 month into Mar 3 and skips February; `AdvanceDue` clamps to the month's length instead (Jan 31 → Feb 28) and returns to the anchor afterwards (→ Mar 31). The anchor is set from the due date on create and whenever a `PUT` sends `next_due_date` — so a client should send the date only when the user changed it.
- **An overdue bill stays overdue.** Nothing advances a due date except paying it, because paying books a real expense and a silent advance would hide an unpaid bill.
- **Paying is safe to repeat.** `MarkPaid` advances the due date with a conditional update that matches only while `next_due_date` still equals what was read — and the client's `expected_due_date` — so of two identical requests exactly one succeeds and the other gets **409** before anything is written. Only then is the expense inserted (`source: "subscription"`, dated now, followed by `summaries.InvalidateFor`); if that insert fails, the date is put back.
- **Reminders are not the server's job.** There are no background jobs in this service; the Flutter app schedules notifications on the device from the list it loads.

## Two different "summary" endpoints

- `GET /api/summary/:user_id` (`summary_handler.go`) returns a cached `MonthlySummary` document per `YYYY-MM`, combining **recurring income from the user profile** with one-time income transactions. `is_frozen` is derived from whether the month's window has fully elapsed (never from comparing month strings against the server clock, which let a client an hour ahead freeze a live month at zero). Frozen months are served from cache; the current month is recalculated on read and written back with `ReplaceOne` — a `$set` carrying `_id` is rejected as an immutable-field update and silently left the cache stale.
- `GET /api/transactions/summary/:user_id` (`transaction_handler.go`) is a separate ad-hoc aggregation over transactions only, with no profile income and no caching.

`GET /api/transactions/:user_id` accepts `type`, `category`, `month` (`YYYY-MM`), `search` (case-insensitive merchant fragment), `limit` and `skip`. The `month` filter goes through `summaries.Bounds`, so a filtered list and that month's summary can never disagree about which transactions belong to the month.

They are not interchangeable — check which one a caller actually needs.

**Recurring income is an assumption, not a record.** `calculateMonthlySummary` withholds it from any month that has already elapsed *and* holds no transactions ("elapsed and empty") — otherwise a brand-new user was credited a full salary for months before they signed up, and with no expenses to offset it the dashboard congratulated them for saving it. The test is deliberately not "before signup": a past month containing transactions is evidence of activity, and the seeded demo history depends on still getting the standing income.

## Admin endpoints are unprotected and destructive

Registered outside the `/api` group in `routes.go`:

- `POST /admin/seed-transactions?user_id=…` — inserts ~45 hardcoded Nov 2025–Apr 2026 Thai transactions. This is what makes the coach and the dashboard charts demoable.
- `DELETE /admin/reset-summaries`, `DELETE /admin/reset-transactions` — wipe data. Never call these without an explicit instruction.
