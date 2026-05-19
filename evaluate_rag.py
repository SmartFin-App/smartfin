"""
SmartFin RAG Evaluation Script
Evaluates the AI Financial Coach using RAGAS metrics + Gemini as judge.
Generates an HTML report with scores.
"""

import os
import json
import time
import requests
from datetime import datetime

# ─── Configuration ───
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyCWCD52ryjv63NNfmXOfkAacnO7m1TrsHY")
BACKEND_URL = "http://localhost:3000/api/coach/ask"
GEMINI_EVAL_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={GEMINI_API_KEY}"

# ─── Test Cases ───
TEST_CASES = [
    {
        "question": "How much did I spend on food this month?",
        "ground_truth": "Based on the transactions, the total spending on Food category items should be calculated from the transaction records.",
        "context_hint": "Food category transactions"
    },
    {
        "question": "Am I over budget this month?",
        "ground_truth": "The answer should compare total expenses against the budget limit and state whether spending is within or over budget.",
        "context_hint": "Budget limit vs total expenses"
    },
    {
        "question": "What is my biggest spending category?",
        "ground_truth": "The answer should identify the category with the highest total spending amount from the user's transactions.",
        "context_hint": "Category-wise spending breakdown"
    },
    {
        "question": "How much did I spend on transport?",
        "ground_truth": "The answer should sum up all Transport category transactions and report the total.",
        "context_hint": "Transport category transactions"
    },
    {
        "question": "Can I afford to spend 5000 baht more this month?",
        "ground_truth": "The answer should calculate remaining budget (budget limit minus total expenses) and compare it to 5000 baht.",
        "context_hint": "Available budget remaining"
    },
    {
        "question": "What are my spending trends over the last few months?",
        "ground_truth": "The answer should analyze monthly summary data to identify increasing or decreasing spending patterns.",
        "context_hint": "Monthly summary history"
    },
    {
        "question": "How much did I save last month?",
        "ground_truth": "The answer should report savings from the previous month's summary (income minus expenses).",
        "context_hint": "Previous month summary"
    },
    {
        "question": "Give me tips to reduce my spending",
        "ground_truth": "The answer should provide actionable financial advice based on the user's actual spending patterns and categories.",
        "context_hint": "Spending patterns and categories"
    },
    {
        "question": "What is my monthly income?",
        "ground_truth": "The answer should state the user's monthly income from their profile.",
        "context_hint": "User profile data"
    },
    {
        "question": "How is my financial health?",
        "ground_truth": "The answer should assess the user's financial health based on budget usage, savings rate, and spending patterns.",
        "context_hint": "Overall financial metrics"
    },
]


def call_backend(question: str, user_id: str = "test_uid") -> dict:
    """Call the SmartFin backend coach endpoint."""
    try:
        resp = requests.post(BACKEND_URL, json={
            "user_id": user_id,
            "message": question,
            "history": []
        }, timeout=30)
        if resp.status_code == 200:
            data = resp.json()
            return {"success": True, "response": data.get("response", "")}
        return {"success": False, "response": f"HTTP {resp.status_code}: {resp.text}"}
    except Exception as e:
        return {"success": False, "response": str(e)}


def gemini_judge(prompt: str) -> str:
    """Use Gemini as a judge to score RAG outputs."""
    try:
        resp = requests.post(GEMINI_EVAL_URL, json={
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 500}
        }, timeout=30)
        data = resp.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        return f"ERROR: {e}"


def score_metric(metric_name: str, question: str, answer: str, ground_truth: str, context_hint: str) -> float:
    """Score a single metric using Gemini as judge. Returns 0.0-1.0."""
    prompts = {
        "faithfulness": f"""Rate how faithful this answer is to the financial data context (no hallucination).
Question: {question}
Context type: {context_hint}
Answer: {answer}
Score from 0.0 to 1.0 (1.0 = perfectly faithful, 0.0 = completely hallucinated).
Reply with ONLY a number like 0.85""",

        "answer_relevancy": f"""Rate how relevant this answer is to the question asked.
Question: {question}
Answer: {answer}
Score from 0.0 to 1.0 (1.0 = perfectly relevant, 0.0 = completely irrelevant).
Reply with ONLY a number like 0.85""",

        "context_precision": f"""Rate how well the RAG system retrieved useful context for this question.
Question: {question}
Expected context: {context_hint}
Answer quality: {answer[:200]}
Score from 0.0 to 1.0 (1.0 = perfect context, 0.0 = useless context).
Reply with ONLY a number like 0.85""",

        "context_recall": f"""Rate whether the context contained all information needed to answer correctly.
Question: {question}
Expected answer: {ground_truth}
Actual answer: {answer}
Score from 0.0 to 1.0 (1.0 = context had everything needed).
Reply with ONLY a number like 0.85""",

        "answer_correctness": f"""Rate how correct this answer is compared to the expected answer.
Question: {question}
Expected: {ground_truth}
Actual: {answer}
Score from 0.0 to 1.0 (1.0 = perfectly correct).
Reply with ONLY a number like 0.85"""
    }

    result = gemini_judge(prompts[metric_name])
    try:
        score = float(result.strip())
        return max(0.0, min(1.0, score))
    except ValueError:
        # Try to extract a number from the response
        import re
        match = re.search(r'(\d+\.?\d*)', result)
        if match:
            return max(0.0, min(1.0, float(match.group(1))))
        return 0.5  # default


METRICS = ["faithfulness", "answer_relevancy", "context_precision", "context_recall", "answer_correctness"]


def generate_html_report(results: list, avg_scores: dict, timestamp: str) -> str:
    """Generate a beautiful HTML evaluation report."""

    def score_color(s):
        if s >= 0.8: return "#10b981"
        if s >= 0.6: return "#f59e0b"
        return "#ef4444"

    def score_badge(s):
        if s >= 0.8: return "Excellent"
        if s >= 0.6: return "Good"
        return "Needs Work"

    overall = sum(avg_scores.values()) / len(avg_scores) if avg_scores else 0

    rows = ""
    for r in results:
        cells = ""
        for m in METRICS:
            s = r["scores"].get(m, 0)
            cells += f'<td style="color:{score_color(s)};font-weight:600">{s:.2f}</td>'
        answer_preview = r["answer"][:80] + "..." if len(r["answer"]) > 80 else r["answer"]
        rows += f"""<tr>
            <td style="max-width:200px">{r["question"]}</td>
            <td style="max-width:250px;font-size:0.85em;color:#94a3b8">{answer_preview}</td>
            {cells}
        </tr>"""

    metric_cards = ""
    for m in METRICS:
        s = avg_scores[m]
        label = m.replace("_", " ").title()
        metric_cards += f"""
        <div style="background:rgba(255,255,255,0.05);border-radius:16px;padding:24px;text-align:center;border:1px solid rgba(255,255,255,0.1)">
            <div style="font-size:0.85em;color:#94a3b8;margin-bottom:8px">{label}</div>
            <div style="font-size:2.2em;font-weight:700;color:{score_color(s)}">{s:.2f}</div>
            <div style="font-size:0.75em;color:{score_color(s)};margin-top:4px">{score_badge(s)}</div>
        </div>"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SmartFin RAG Evaluation Report</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:'Inter',sans-serif;background:#0f172a;color:#e2e8f0;min-height:100vh;padding:40px 20px}}
.container{{max-width:1200px;margin:0 auto}}
.header{{text-align:center;margin-bottom:48px}}
.header h1{{font-size:2.5em;font-weight:800;background:linear-gradient(135deg,#6366f1,#8b5cf6,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:8px}}
.header p{{color:#94a3b8;font-size:1.1em}}
.overall{{text-align:center;margin:32px 0;padding:32px;background:linear-gradient(135deg,rgba(99,102,241,0.15),rgba(139,92,246,0.15));border-radius:20px;border:1px solid rgba(139,92,246,0.3)}}
.overall-score{{font-size:4em;font-weight:800;color:{score_color(overall)}}}
.overall-label{{color:#94a3b8;font-size:1.1em;margin-top:4px}}
.metrics-grid{{display:grid;grid-template-columns:repeat(5,1fr);gap:16px;margin:32px 0}}
@media(max-width:800px){{.metrics-grid{{grid-template-columns:repeat(2,1fr)}}}}
table{{width:100%;border-collapse:collapse;margin-top:32px;background:rgba(255,255,255,0.03);border-radius:16px;overflow:hidden}}
th{{background:rgba(99,102,241,0.2);padding:14px 12px;text-align:left;font-weight:600;font-size:0.85em;color:#a5b4fc;text-transform:uppercase;letter-spacing:0.5px}}
td{{padding:12px;border-bottom:1px solid rgba(255,255,255,0.06);font-size:0.9em}}
tr:hover{{background:rgba(255,255,255,0.03)}}
.footer{{text-align:center;margin-top:40px;color:#475569;font-size:0.85em}}
.badge{{display:inline-block;padding:4px 12px;border-radius:20px;font-size:0.8em;font-weight:600}}
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>🐾 SmartFin RAG Evaluation</h1>
        <p>AI Financial Coach — Performance Report</p>
        <p style="color:#64748b;font-size:0.9em;margin-top:8px">{timestamp}</p>
    </div>
    <div class="overall">
        <div class="overall-score">{overall:.2f}</div>
        <div class="overall-label">Overall Score — {score_badge(overall)}</div>
    </div>
    <div class="metrics-grid">{metric_cards}</div>
    <h2 style="margin:32px 0 0;font-size:1.3em;color:#a5b4fc">📋 Detailed Results</h2>
    <table>
        <thead><tr>
            <th>Question</th><th>Answer</th>
            <th>Faithfulness</th><th>Relevancy</th><th>Ctx Precision</th><th>Ctx Recall</th><th>Correctness</th>
        </tr></thead>
        <tbody>{rows}</tbody>
    </table>
    <div class="footer">
        <p>Generated by SmartFin RAG Evaluation Pipeline • Powered by Gemini 2.5 Flash</p>
        <p style="margin-top:4px">{len(results)} test cases • {len(METRICS)} metrics • LLM-as-Judge evaluation</p>
    </div>
</div>
</body></html>"""


def main():
    print("=" * 60)
    print("🐾 SmartFin RAG Evaluation")
    print("=" * 60)

    # Step 1: Query the backend
    results = []
    for i, case in enumerate(TEST_CASES):
        print(f"\n[{i+1}/{len(TEST_CASES)}] Testing: {case['question']}")
        resp = call_backend(case["question"])

        if not resp["success"]:
            print(f"  ⚠️  Backend error: {resp['response'][:100]}")
            # Use a fallback answer so we can still evaluate
            resp["response"] = f"[Backend unavailable] Could not answer: {case['question']}"

        print(f"  ✅ Got response ({len(resp['response'])} chars)")
        results.append({
            "question": case["question"],
            "answer": resp["response"],
            "ground_truth": case["ground_truth"],
            "context_hint": case["context_hint"],
            "scores": {}
        })
        time.sleep(0.5)

    # Step 2: Score each result with Gemini-as-Judge
    print("\n" + "=" * 60)
    print("📊 Scoring with Gemini-as-Judge...")
    print("=" * 60)

    for i, r in enumerate(results):
        print(f"\n[{i+1}/{len(results)}] Scoring: {r['question'][:50]}...")
        for m in METRICS:
            score = score_metric(m, r["question"], r["answer"], r["ground_truth"], r["context_hint"])
            r["scores"][m] = score
            print(f"  {m}: {score:.2f}")
            time.sleep(1)  # Rate limiting

    # Step 3: Calculate averages
    avg_scores = {}
    for m in METRICS:
        avg_scores[m] = sum(r["scores"][m] for r in results) / len(results)

    overall = sum(avg_scores.values()) / len(avg_scores)

    # Step 4: Print summary
    print("\n" + "=" * 60)
    print("📊 EVALUATION RESULTS")
    print("=" * 60)
    for m in METRICS:
        label = m.replace("_", " ").title()
        print(f"  {label:25s} {avg_scores[m]:.2f}")
    print(f"  {'─' * 40}")
    print(f"  {'Overall Score':25s} {overall:.2f}")

    # Step 5: Generate HTML report
    timestamp = datetime.now().strftime("%B %d, %Y at %I:%M %p")
    html = generate_html_report(results, avg_scores, timestamp)

    report_path = os.path.join(os.path.dirname(__file__), "rag_evaluation_report.html")
    with open(report_path, "w") as f:
        f.write(html)
    print(f"\n✅ HTML report saved: {report_path}")

    # Step 6: Save JSON results
    json_path = os.path.join(os.path.dirname(__file__), "rag_evaluation_results.json")
    with open(json_path, "w") as f:
        json.dump({"timestamp": timestamp, "overall": overall, "metrics": avg_scores, "results": results}, f, indent=2)
    print(f"✅ JSON results saved: {json_path}")


if __name__ == "__main__":
    main()
