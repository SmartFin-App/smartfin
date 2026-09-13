# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is the monorepo-level guide. Each half has its own, loaded automatically when you work in it:

- `smartfin-flutter/CLAUDE.md` — Flutter client
- `smartfin-backend/CLAUDE.md` — Go API

## What this is

SmartFin is a personal finance copilot for **Thai users**, split into a Flutter client and a Go API. Two features define it: scanning Thai mobile-banking e-slips (PromptPay, K PLUS, SCB EASY, Krungthai NEXT, BBL) with Gemini Vision, and an agentic-RAG "AI Coach" that reasons over the user's own MongoDB data via Gemini function calling.

Consequences that apply on both sides of the wire:

- **Money is always integer Thai Baht (฿), never a float.** Go models use `int64` and send preformatted `formatted_amount` strings; the client renders them as-is rather than doing its own math.
- **Slip parsing must handle Thai script and Buddhist-era years** (2567/2569 → Gregorian), which is why the extraction prompt in `scanner_handler.go` is explicit about both.
- The coach persona is warm and uses a 🐾 paw emoji — user-facing copy on both sides follows that.

The root `README.md` says the backend uses **Gin**; it actually uses **Fiber v2**.

## Commands

```bash
# Backend — Go 1.26
cd smartfin-backend && go run cmd/main.go      # serves on $PORT (default 3000)
cd smartfin-backend && go test ./...

# Frontend — Dart ^3.11.1
cd smartfin-flutter && flutter pub get && flutter run
cd smartfin-flutter && flutter analyze && flutter test
```

The backend must be running on port 3000 for the app to get past its auth screens. Per-target run flags, single-test invocations, and env vars are in the nested files.

## How the halves fit together

- **Identity:** Firebase handles login on the client; the backend keys every record by the **Firebase UID string** and does not verify tokens. The UID travels as a plain path param or body field.
- **Slip scanning is stateless server-side.** `POST /api/scanner/process` extracts fields with Gemini Vision and persists nothing — the app's verify screen is what creates the transaction after the user confirms.
- **The coach is a multi-turn agentic loop**, budgeted at 45s server-side, which is why the client's Dio receive timeout must stay above that (it is 60s). Some of its tools *write* to the database (savings goal, budget limit, add transaction) and report back as `actions_taken`.
- **Base URLs are hardcoded per platform** in the client, including a LAN IP for physical Android devices that goes stale when the host Mac's address changes.
- **Time is Thai local (+07:00) on every surface the user or the model sees.** Month windows come from `summaries.Bounds`, and the agent is given the current date plus timestamps already converted to +07:00 — MongoDB returns UTC, and passing that through unconverted put the coach's memory on the wrong day.
- **Subscriptions & bills are entered by hand and reminded on the device.** The API derives every due-date field in Thai time and makes paying a bill safe to repeat; the Flutter app schedules the reminders as local notifications, because the backend runs no background jobs. The coach can read the bills (`get_subscriptions`) but never pays one.
- **The coach's transcript lives server-side** in `chat_messages` and is read back through `GET /api/coach/history/:user_id`. The Flutter coach screen is disposed on every tab switch, so it cannot hold the conversation itself.

## Exercising the API

`API postman/` holds Postman collections. Coach answer quality is measured by `smartfin-backend/cmd/eval`: 30 scripted questions scored by rule against figures recomputed from MongoDB, compared with no-retrieval and one-shot RAG baselines. It replaced a RAGAS-style `evaluate_rag.py` whose Gemini judge had no ground truth. Re-run it after changing agent prompts or tools; see the backend CLAUDE.md.

## Destructive endpoints

The backend registers unprotected admin routes outside `/api`: `POST /admin/seed-transactions?user_id=…` (inserts ~45 hardcoded Nov 2025–Apr 2026 Thai transactions, which is what makes the coach and charts demoable), plus `DELETE /admin/reset-summaries` and `DELETE /admin/reset-transactions`. Never call the delete routes without an explicit instruction.
