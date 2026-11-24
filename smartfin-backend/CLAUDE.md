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
./deploy.sh                               # build and roll out to Cloud Run (see Deployment)
```

`.env` is loaded by godotenv at startup; a missing `MONGODB_URI` or `DB_NAME` is a `log.Fatal`. Variables: `MONGODB_URI`, `DB_NAME`, `PORT`, `GEMINI_API_KEY`, optional `SERPAPI_API_KEY`, and `ADMIN_API_KEY` (unset = the `/admin` routes are off).

Tests live in `internal/agents`, `internal/auth` (token and UID checks against a fake verifier), `internal/handlers` (only the scanner's not-a-slip rule), `internal/insights`, `internal/models`, `internal/routes` and `internal/summaries` (the date, projection and insight rules are pure functions tested against fixed data). The whole suite runs offline in about a second.

## Stack details that are easy to guess wrong

- **Fiber v2** (`*fiber.Ctx`), not Gin or net/http — the root README misstates this.
- **`mongo-driver/v2`**: IDs are `bson.ObjectID` (not `primitive.ObjectID`), and `mongo.Connect` takes options only, with no context argument.
- Gemini via `google.golang.org/genai` (the older `google/generative-ai-go` cannot carry the thought signatures Gemini 3 tool calls require); the model everywhere is `config.GeminiModel`, currently `gemini-3.5-flash-lite` (chosen for its 15 requests/minute free-tier limit; full-size flash models get 5).
- Money is **integer Thai Baht** — `int64` throughout, formatted with `฿` and comma separators, never a float and never decimals.

## Structure

`cmd/main.go` → `internal/routes/routes.go` → `internal/handlers/` → `internal/agents/`.

`config/database.go` exposes package globals `config.DB` and `config.GetCollection(name)`; handlers reach for collections directly, so there is no repository or service layer to thread changes through. Collections: `users`, `transactions`, `monthly_summaries`, `chat_messages`, `subscriptions`.

**Every index the app relies on is declared in `config/indexes.go`** and created at startup by `EnsureIndexes` (idempotent, and non-fatal — a missing index costs speed, not correctness). Keys are ordered equality-then-sort (`{user_id, date: -1}`, `{user_id, created_at: -1}`), which is what lets one index serve both the filter and the sort. **If you add a user-scoped query, add its index there**, or it becomes a collection scan.

`internal/summaries` is the one shared piece of domain logic: it owns the month-window rules and cache invalidation used by both the handlers and the agents. **Never compute a month boundary inline** — call `summaries.Bounds` / `summaries.StringOf`. Windows are anchored to a fixed +07:00 (`summaries.Zone`), not UTC, so a 06:00 Bangkok expense on the 1st is filed under the right month. Any write that touches a transaction must call `summaries.Invalidate`/`InvalidateFor`, including for frozen months — a backdated entry is exactly the case that otherwise stays invisible to every total.

**Users are keyed by Firebase UID** (`firebase_uid` string), not by Mongo `_id` — every user-scoped query filters on that string. The UID still arrives as a path param, query parameter, body field or form field, but **every `/api` request must also prove it** (`internal/auth`, added 15 Nov 2026 to close defect D-02 / NFR-04):

- `auth.Middleware` on the `/api` group verifies `Authorization: Bearer <Firebase ID token>` with the Firebase Admin SDK (`VerifyIDToken`, project `FIREBASE_PROJECT_ID`, default `fir-auth-login-udacity`; it needs no service-account credentials) and answers **401** without a valid one. It then answers **403** if `user_id` / `firebase_uid` in the query string or the body names anyone other than the token's UID.
- **The body check must read the body the way handlers do.** Handlers use Fiber's `BodyParser`, which also accepts vendor and text JSON (`application/vnd.api+json`, `text/json`), XML, and form keys matching a field name in any case (`UserID`, `userid`). Checking only `application/json` and the form key `user_id` let a signed-in user act as someone else in those formats. `claimedUIDs` therefore runs `BodyParser` into a struct with the handlers' field names and tags (`UserID` / `json:"user_id"`, `FirebaseUID` / `json:"firebase_uid"`), and also normalises form keys. **A handler that reads a UID through a differently named field must be added there**, and `TestMiddlewareEveryBodyFormat` covers each format.
- Path parameters are not known yet when a group middleware runs, so every route with a UID in its path takes `auth.OwnParam("user_id")` or `auth.OwnParam("firebase_uid")` in `routes.go`. **A new user-scoped route needs one too**, or a valid token for user A can read user B's data through the path.
- Handlers are unchanged and still read the UID from the request: by the time they run it has been proved. `auth.UID(c)` returns the verified UID if a handler ever needs it directly.
- **Harness requests**: a valid `X-Admin-Key` (`ADMIN_API_KEY`) replaces the token, but such a request may only name test users whose UID starts with `eval-` or `tds-` (real Firebase UIDs never contain a hyphen). `cmd/eval` and `cmd/slipeval` send the key on every request. With `ADMIN_API_KEY` unset there is no harness path at all.
- `main.go` treats a verifier that cannot be built as fatal, so the API never starts unchecked. `/health` and `/admin` sit outside `/api` and are unaffected. Postman requests to `/api` now need an ID token, or the admin key with an `eval-` user.

The single-transaction routes (`GET /api/transactions/detail/:id`, `PUT`, `DELETE`) additionally require a `user_id` (query string or body) and filter on it via `ownerFromRequest` — without that they had no notion of an owner at all, so a guessed ObjectID reached another user's record. The auth middleware checks that `user_id` against the token like any other.

`routes.go` also holds the admin endpoints inline (see below); the demo expenses they seed are in `seed.go`.

## The coach is an agentic loop, not one-shot RAG

`internal/agents/orchestrator.go` backs `POST /api/coach/ask` (45s handler timeout). It builds a system prompt grounded in the user's profile, declares **8 tools**, then runs a **max-5-iteration** Gemini function-calling loop, dispatching through `dispatchTool` to three sub-agents:

| Agent | Tools |
| --- | --- |
| `retrieval_agent.go` | `get_budget_summary`, `get_transactions`, `get_spending_insights`, `get_subscriptions`, `get_recent_conversations` |
| `action_agent.go` | `update_budget_limit`, `add_transaction` (expenses only) — these **write** to Mongo and are echoed back to the client as `actions_taken` |
| `research_agent.go` | `web_search` — SerpAPI if `SERPAPI_API_KEY` is set, else scrapes DuckDuckGo HTML, else `searchUnavailable`: no results and no figures |

When working on this loop:

- Tool results must pass through `sanitizeForGemini` (a JSON round-trip) before being returned as a `genai.FunctionResponse`, or protobuf conversion fails on types that aren't plain `map[string]any` / `[]any`.
- Adding or removing a tool means updating `agent_test.go`, which asserts **exactly 8** declarations and checks each by name.
- `get_transactions` has **no date filter** and returns the newest rows (default 20; a limit above 100 silently becomes 30). Questions about one shop or service must use its optional `merchant` filter (case-insensitive fragment) — before it existed, the coach could not answer "how much have I spent at Netflix?" and the evaluation traced 7 of 13 failures to it. The category filter is an escaped, case-insensitive prefix; the declaration lists the real category names because the model otherwise invents ones like "Healthcare".
- `get_subscriptions` is deliberately **read-only**. The system prompt tells the model to send a user who says "I paid my Netflix" to the app's Mark paid button instead of calling `add_transaction` — that would log the expense but leave the bill's due date where it was.
- Gemini arguments arrive as `float64` regardless of declared schema type, hence the `args["amount"].(float64)` conversions in `dispatchTool`.
- If the loop exhausts its iterations without producing text, the orchestrator returns a canned "I've checked your data and updated your records" reply rather than an error.
- **A first reply that only promises to check is nudged once.** Gemini sometimes answers "give me a moment to look that up" without calling a tool, and a reply without a tool call used to end the loop — the user got the promise and nothing else. `looksLikeStall` (short text with phrases like "let me check", "สักครู่", "ขอตรวจสอบ") triggers one follow-up asking the model to call the tool now. In the evaluation this took the coach's shared pass rate from 84% to 99%. Keep the phrase list conservative: a real answer that happens to match gets an unnecessary extra model call, not a wrong answer. The coach can still *claim* an action without calling the write tool — that is not fixed.
- **The coach must never be handed a figure nobody retrieved.** When both search backends fail, `web_search` returns `available: false` and an instruction to say the figure could not be checked. It used to return a canned paragraph — a 2.50% policy rate, savings rates, inflation, tax allowances — labelled "Financial Knowledge Base", which the model presented as live ("currently 2.50% (as of mid-2026)"). The system prompt backs this up: a rate, price or allowance may be stated only from a `web_search` result in the same conversation. Likewise `describeProfile` writes "not set" for a missing profile or value; a user with no profile document was once described as earning ฿30,000 with a ฿15,000 budget, and a zero budget read as a real ฿0 limit. Don't reintroduce defaults in either place.
- Every exchange is persisted to `chat_messages` with the tool names used — that is what `get_recent_conversations` later reads back.
- **Everything the model sees is Thai local time.** `get_recent_conversations` and `get_transactions` format through `summaries.Zone` (+07:00) — MongoDB hands back UTC, and passing that through unconverted put chat memory on the wrong *day*. The system prompt also carries the current date and month, because the model has no clock of its own and was otherwise inferring "today" from training data.
- `get_recent_conversations` defaults to 20 messages. Note the guard in `retrieval_agent.go`: anything **above** 20 silently collapses to 6, so raising the default past the cap returns *fewer* messages, not more.
- **`get_spending_insights` answers "what are my bad expenses?"** (asked by the project advisor in Oct 2026; the coach had no way to answer it). The rules live in `internal/insights`, are deterministic, and judge a month only against the user's own earlier history: unusual purchases (median/MAD robust z ≥ 3.5, ≥ 3× the category's typical amount and ≥ ฿1,000), small habits (one merchant ≥ 4 times a month at ≤ ฿500 typical, ≥ ฿1,000 total), categories up ≥ 30% and ≥ ฿1,000 on the average of the previous 3 months (only months with expenses count, so a gap such as demo data followed by real use is not read as ฿0 months; at least 2 needed), the discretionary share, and two or more active subscriptions in one discretionary category. **Bills, Groceries, Health and Transport are never flagged**, and `Other` (mostly transfers to people) is not judged. Every item carries a `reason` with figures, and the prompt has the coach call them "worth reviewing", not bad. With no month (or `current`) and no expenses yet this month, it analyses the latest month that has expenses and says so in `note`.
- It replaces `detect_spending_anomalies` (removed in `53f79be`), which used mean and standard deviation, so one big purchase inflated the spread enough to hide itself or a second one. The external ML-service integration (`12827ac`) stays removed. A trained classifier has no labels to learn "bad" from and could not be scored against ground truth.

### Evaluating the coach (`cmd/eval`)

`cmd/eval` scores the coach against answers that can be checked. It creates throwaway `eval-<run>-*` users through the API (profile, the 53 seeded expenses, three bills dated relative to the run day), asks 30 scripted questions (`cmd/eval/cases.go`), and scores every answer **by rule against figures recomputed from MongoDB** — no LLM judge. The same questions go to two baselines on the same model and temperature: no retrieval, and one-shot RAG with the user's complete records pasted into the prompt.

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

`scanner_handler.go` (`POST /api/scanner/process`) takes multipart `image` + `user_id`, calls Gemini Vision at temperature 0 with a prompt demanding bare JSON, strips ```` ```json ```` fences before unmarshalling, and returns `{merchant, amount, date, category, confidence, raw_text}`. On a parse failure it returns `Unknown Merchant` / 0 / today rather than erroring, so the user can still correct it downstream.

The prompt also asks for a **category**, which the verify screen preselects. The reply passes through `models.NormalizeCategory`, so only the eight names in `models.ExpenseCategories` reach the client and anything else becomes `Other`. The prompt tells the model to answer `Other` for a transfer to a person's name: such a slip says nothing about what was bought, and before this every scan opened as a hardcoded "Food". `cmd/slipeval` does not score the category, because `labels.csv` has no category column.

The extraction prompt is explicit about **Thai script transliteration and Buddhist-era years** (2567/2569 → Gregorian) because the inputs are Thai mobile-banking e-slips (PromptPay, K PLUS, SCB EASY, Krungthai NEXT, BBL). Keep both requirements if you rewrite it.

**Photos that are not slips get a 422, not a guess.** The prompt asks for `is_slip`, and an explicit `false` returns `422 {"error", "code": "not_a_slip"}`, which the app shows as "This doesn't look like a slip". A reply without the field is still treated as a slip, so a model that drops it falls back to the old behaviour instead of refusing every scan. This is the backstop: the app reads each photo's text on the device first and never uploads one with no amount in it, so most non-slips never reach Gemini. Before either check, a photo of a meal opened verify as `Unknown Merchant` / ฿0. `cmd/slipeval` counts a 422 as an error, so a real slip turned away shows up there.

This handler writes **nothing** to Mongo — the Flutter app creates the transaction separately after the user confirms on the verify screen.

Two fallbacks hide failures from callers, so check them when evaluating: an unparseable model reply returns `Unknown Merchant` / 0, and a missing date silently becomes **today** (server local time), which makes a receipt with no printed date look correctly dated.

### Evaluating the scanner (`cmd/slipeval`)

`go run ./cmd/slipeval -repeats 2` sends every image in `eval-slips/images/` to `/api/scanner/process` as the app does (original file, multipart) and compares merchant, amount and date with `eval-slips/labels.csv`. **`eval-slips/` is git-ignored and must stay that way** — real slips carry names, account numbers and reference IDs; `summary.md` deliberately reports only file names and right/wrong marks. Rules: amount within ±฿0.5 (the scanner returns whole baht), merchant = normalised name contains any `|`-separated alias (Thai names are transliterated, so exact matching is unfair), date exact, and a blank label date means "not printed" and is excluded. Scans are saved raw, so after correcting a label run `go run ./cmd/slipeval -rescore eval-slips/results/<run>` — no new Gemini calls. Labels marked unverified are flagged in the summary. The harness does not retry, so on a rate-limited model pace it with `-concurrency 1 -interval 4500ms`; unpaced, a third of the scans come back as HTTP 500.

## Endpoints beyond the obvious CRUD

- `GET /api/coach/history/:user_id` — the stored transcript, newest-first internally then reversed so the client renders top-down. The orchestrator has always persisted both sides of every exchange; this is what reads it back. The Flutter coach screen is disposed on every tab switch, so the transcript **must** come from here rather than widget state.
- **There is no income and no savings goal.** SmartFin tracks spending only. `monthly_income`, `income_bracket` and the `savings_goal*` fields were removed from `User`, and `UpdateUserRequest` ignores them if a stale client sends them. Summaries count expense transactions only, `GET /api/transactions/:user_id` returns expenses only, and creating or editing a transaction as `income` is refused with 400. Income rows written before the change stay in Mongo but never surface. The savings-goal endpoint, `summaries.ProjectGoal` and the coach's `set_savings_goal` tool are gone, and two evaluation cases went with them (A5 "how much did I save", W2 "set a savings goal").
- **A shared slip stores the user's share as `amount`.** `POST /api/transactions` takes optional `split_total` (what the slip was for) and `split_people` (head count, the user included), checked by `models.ValidateSplit`: both or neither, 2–100 people, and the share cannot exceed the total. They are a note for the detail screen only — every total, budget and coach tool reads `amount`, so nothing else needs to know about splits. A `PUT` that raises the amount above `split_total` unsets both.
- `GET /api/transactions/duplicates/:user_id?amount=[&date=]` — up to three expenses with that amount (or that `split_total`) inside `summaries.DuplicateWindow`: the Thai day before the slip's date through the day after. The verify screen calls it before saving, because marking a bill paid and scanning that payment's slip otherwise book the same money twice. **It informs a warning and refuses nothing** — two real payments can share an amount — so don't turn it into a uniqueness rule on create.
- `DELETE /api/users/:firebase_uid` — erases the profile, transactions, summaries, chat messages and subscriptions. Owned records go first, so a partial failure leaves a recoverable account rather than orphaned data. Irreversible; the token check and `OwnParam` limit it to the signed-in user.
- `POST|GET|DELETE /api/users/:firebase_uid/photo` — avatars in a GridFS bucket, filename = the UID. **`photo_url` is stored as a relative path** (`/api/users/<uid>/photo`), never an absolute URL: the API host changes between emulator, LAN device and deployment, and a baked-in URL rots the moment it does.

`UpdateUser` binds to `models.UpdateUserRequest`, a typed partial with **pointer fields** — that is what keeps "absent" distinguishable from "set to zero", so clearing the budget is a real write rather than a no-op. It also keeps money as `int64` instead of a JSON `float64` that lands in Mongo as a double, and means an unknown key can no longer be `$set` into the document.

## Subscriptions & bills

`subscription_handler.go` serves a tracker of recurring bills the user enters by hand: `POST /api/subscriptions`, `GET /api/subscriptions/:user_id[?active=true]`, `PUT|DELETE /api/subscriptions/:id` (owner-scoped through `ownerFromRequest`, like single transactions) and `POST /api/subscriptions/:id/pay`. The date rules are pure functions in `internal/summaries/subscriptions.go`, unit-tested against a fixed clock.

- **A due date is a Thai calendar day**, stored as midnight +07:00 and parsed with `summaries.ParseDueDate` — never `parseTxDate`, which reads a date-only string as UTC midnight. Mongo hands the instant back as 17:00 UTC the day before, so the API also sends `due_date` (`"2026-09-14"`), `days_until_due`, `status` (`paused | overdue | due_today | due_soon | upcoming`) and `formatted_due_date`, and clients are expected to use those rather than converting `next_due_date` themselves. The list adds `monthly_total` (every active bill at its monthly equivalent), `overdue_count`, `due_soon_count` and `due_soon_total`.
- **`anchor_day` keeps month-end bills on their day.** `time.AddDate` turns Jan 31 + 1 month into Mar 3 and skips February; `AdvanceDue` clamps to the month's length instead (Jan 31 → Feb 28) and returns to the anchor afterwards (→ Mar 31). The anchor is set from the due date on create and whenever a `PUT` sends `next_due_date` — so a client should send the date only when the user changed it.
- **An overdue bill stays overdue.** Nothing advances a due date except paying it, because paying books a real expense and a silent advance would hide an unpaid bill.
- **Paying is safe to repeat.** `MarkPaid` advances the due date with a conditional update that matches only while `next_due_date` still equals what was read — and the client's `expected_due_date` — so of two identical requests exactly one succeeds and the other gets **409** before anything is written. Only then is the expense inserted (`source: "subscription"`, dated now, followed by `summaries.InvalidateFor`); if that insert fails, the date is put back.
- **`skip_expense: true` moves the due date without booking anything.** The app sends it when the payment is already in the user's history (its slip was scanned), which it finds through `GET /api/transactions/duplicates/:user_id` with no `date` — the server then searches around its own Thai today. The 409 guards apply exactly as for a normal payment; the reply is 200 with no `transaction`.
- **Reminders are not the server's job.** There are no background jobs in this service; the Flutter app schedules notifications on the device from the list it loads.

## Two different "summary" endpoints

- `GET /api/summary/:user_id` (`summary_handler.go`) returns a cached `MonthlySummary` document per `YYYY-MM`: expense total, category breakdown, and spending against the profile's `budget_limit`. `is_frozen` is derived from whether the month's window has fully elapsed (never from comparing month strings against the server clock, which let a client an hour ahead freeze a live month at zero). Frozen months are served from cache; the current month is recalculated on read and written back with `ReplaceOne` — a `$set` carrying `_id` is rejected as an immutable-field update and silently left the cache stale.
- `GET /api/transactions/summary/:user_id` (`transaction_handler.go`) is a separate ad-hoc aggregation over transactions only, with no profile income and no caching.

`GET /api/transactions/:user_id` accepts `type`, `category`, `month` (`YYYY-MM`), `search` (case-insensitive merchant fragment), `limit` and `skip`. The `month` filter goes through `summaries.Bounds`, so a filtered list and that month's summary can never disagree about which transactions belong to the month.

They are not interchangeable — check which one a caller actually needs.


## Admin endpoints are destructive and key-guarded

Registered outside the `/api` group in `routes.go`, behind `adminGuard` (`internal/routes/admin.go`): every request needs an `X-Admin-Key` header equal to `ADMIN_API_KEY`. **With `ADMIN_API_KEY` unset the routes are switched off** (404), so a deployment that forgets the variable fails closed — set it in your local `.env` to keep using them.

- `POST /admin/seed-transactions?user_id=…` — inserts 53 hardcoded Nov 2025–Apr 2026 Thai expenses (`seed.go`). This is what makes the coach and the dashboard charts demoable. April carries the spending `get_spending_insights` flags (a concert ticket, repeated Starbucks and Line MAN orders); `seed_test.go` checks that, plus the shape the eval's fixed answers rely on (January the top month, Shopping December's top category). `cmd/eval` calls it and sends the key from its own `ADMIN_API_KEY`, so export the same value in the harness's shell.
- `DELETE /admin/reset-summaries`, `DELETE /admin/reset-transactions` — wipe data. Never call these without an explicit instruction.

## Deployment

The API runs on **Google Cloud Run** as service `smartfin-api` in asia-southeast1, inside the app's Firebase project `fir-auth-login-udacity` (first deployed 15 Nov 2026). `./deploy.sh` uploads this folder to Cloud Build, which builds the `Dockerfile` (a static binary from `./cmd` with `golang:1.26`, run on `distroless/static` as non-root), then rolls out a new revision. No local Docker is needed. `./deploy.sh --setup` is the one-time part: it enables the APIs, creates the runtime service account `smartfin-api@…`, and copies `GEMINI_API_KEY`, `MONGODB_URI` and `ADMIN_API_KEY` from `.env` into Secret Manager as `smartfin-gemini-api-key`, `smartfin-mongodb-uri` and `smartfin-admin-api-key`. Re-run it after changing one of those keys; it deploys afterwards, so the new value is in use straight away.

- **The script is the service's configuration.** Every deploy sets the env vars, the secrets, `--max-instances 2`, `--timeout 120` (above the coach's 45s budget) and public access. A setting changed in the console is reverted by the next `./deploy.sh`, so change it in the script.
- The runtime account can read those three secrets and nothing else. `DB_NAME` is a plain env var, and Cloud Run sets `PORT` (8080). The `Warning: Error loading .env file` lines at startup are expected, because the image has no `.env`.
- **`.gcloudignore` decides what is uploaded.** Without it gcloud falls back to this folder's `.gitignore`, which does not list `eval-slips/` (the root one does), so real slips would be uploaded with the source. `.dockerignore` only keeps files out of the image.
- **The first build on a fresh project fails with `PERMISSION_DENIED`** ("the default service account is missing required IAM permissions"). Builds run as the Compute Engine default account, which enabling Cloud Run creates with the Editor role, and the grant takes a few minutes to take effect. Run `./deploy.sh` again. This happened on the first deploy here.
- **Atlas must allow `0.0.0.0/0`**, since Cloud Run has no fixed outbound IP. `ConnectDB` is fatal, so a revision that cannot reach Atlas never starts listening, and the deploy reports a container that failed to start.
- **The service is public but every `/api` request needs a verified Firebase ID token**, as on the local server. The instance cap bounds cost; the token bounds access. Keep the URL out of this public repo, but don't treat it as a secret: it follows from the service name and the project number, which the committed Firebase config contains. `gcloud run services describe smartfin-api --region asia-southeast1 --format 'value(status.url)'` prints it.
- Logs: `gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="smartfin-api"' --limit 50`, or the service's Logs tab in the Cloud Run console.
