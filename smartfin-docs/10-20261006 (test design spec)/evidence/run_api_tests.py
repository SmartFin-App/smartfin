"""Executes the API-level test cases of the SmartFin test design specification
against a running backend, under one throwaway user that is deleted at the end.
Writes results to api_results.json."""
import json, sys, time, urllib.request, urllib.error, urllib.parse, uuid, datetime, os, mimetypes, csv, re

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3002"
OUT = sys.argv[2]
SKIP_AI = "--skip-ai" in sys.argv
ICT = datetime.timezone(datetime.timedelta(hours=7))
TODAY = datetime.datetime.now(ICT).date()
UID = "tds-" + TODAY.strftime("%Y%m%d") + "-" + uuid.uuid4().hex[:8]
OTHER = UID + "-other"
MONTH = TODAY.strftime("%Y-%m")


def call(method, path, body=None, raw=None, headers=None, timeout=70):
    url = BASE + path
    data = None
    h = dict(headers or {})
    if raw is not None:
        data = raw
    elif body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            txt = r.read().decode()
            code = r.status
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        code = e.code
    try:
        js = json.loads(txt)
    except Exception:
        js = txt
    return code, js


def err(js):
    return js.get("error", "") if isinstance(js, dict) else str(js)[:80]


def d(offset):
    return (TODAY + datetime.timedelta(days=offset)).isoformat()


results = []


def rec(key, ok, actual):
    results.append({"key": key, "status": "Pass" if ok else "Fail", "actual": actual})
    print(("PASS " if ok else "FAIL ") + key + " :: " + actual, flush=True)


def tx(merchant="Test Shop", amount=100, category="Food", **kw):
    b = {"user_id": UID, "merchant": merchant, "amount": amount, "category": category}
    b.update(kw)
    return {k: v for k, v in b.items() if v is not None}


def sub(name="Netflix", amount=419, cycle="monthly", due=None, **kw):
    b = {"user_id": UID, "name": name, "amount": amount, "billing_cycle": cycle,
         "next_due_date": due if due is not None else d(0)}
    b.update(kw)
    return b


def listtx(q=""):
    c, js = call("GET", f"/api/transactions/{UID}?limit=200{q}")
    return js if isinstance(js, list) else []


# ---------------------------------------------------------------- users
c, js = call("POST", "/api/users", {"firebase_uid": UID, "name": "TDS Tester", "email": "tds@example.com", "budget_limit": 15000})
rec("U-create", c == 201 and js.get("firebase_uid") == UID and js.get("budget_limit") == 15000, f"HTTP {c}; profile created with budget_limit {js.get('budget_limit') if isinstance(js, dict) else '?'}")
c, js = call("POST", "/api/users", {"firebase_uid": UID, "name": "TDS Tester", "email": "tds@example.com"})
rec("U-duplicate", c == 409, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/users", {"firebase_uid": UID + "-x", "name": "No Email"})
rec("U-missing-email", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/users/{UID}-nobody")
rec("U-unknown", c == 404, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/users/{UID}", {"budget_limit": -1})
rec("U-budget-neg", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/users/{UID}", {"budget_limit": 0})
c2, js2 = call("GET", f"/api/users/{UID}")
rec("U-budget-zero", c == 200 and js2.get("budget_limit") == 0, f"HTTP {c}; stored budget_limit = {js2.get('budget_limit')}")
c, js = call("PUT", f"/api/users/{UID}", {"budget_limit": 15000})
c2, js2 = call("GET", f"/api/users/{UID}")
rec("U-budget-set", c == 200 and js2.get("budget_limit") == 15000, f"HTTP {c}; stored budget_limit = {js2.get('budget_limit')}")
c, js = call("PUT", f"/api/users/{UID}", {})
rec("U-empty-update", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/users/{UID}", {"monthly_income": 30000, "savings_goal": 5000})
c2, js2 = call("GET", f"/api/users/{UID}")
rec("U-income-ignored", c == 400 and "monthly_income" not in js2, f"HTTP {c}; \"{err(js)}\"; profile has no income field")

# ---------------------------------------------------------------- transactions: create
c, js = call("POST", "/api/transactions", tx("Grab Ride", 150, "Transport", date=f"{MONTH}-05"))
rec("T-valid", c == 201 and js.get("type") == "expense" and js.get("source") == "manual" and js.get("amount") == 150,
    f"HTTP {c}; type={js.get('type')}, source={js.get('source')}, amount={js.get('amount')}")
c, js = call("POST", "/api/transactions", tx("Boundary Shop", 1, "Other", date=f"{MONTH}-09"))
rec("T-amount-1", c == 201 and js.get("amount") == 1, f"HTTP {c}; amount={js.get('amount') if isinstance(js, dict) else ''}")
c, js = call("POST", "/api/transactions", tx("Zero Shop", 0))
rec("T-amount-0", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Negative Shop", -1))
rec("T-amount-neg", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Decimal Shop", 150.75))
rec("T-amount-decimal", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Salary", 30000, "Other", type="income"))
rec("T-income", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("", 100))
rec("T-no-merchant", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("No Category", 100, ""))
rec("T-no-category", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Bad Date", 100, date="10/10/2026"))
rec("T-bad-date", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("No Date Cafe", 60, "Food"))
got = js.get("date", "") if isinstance(js, dict) else ""
okd = False
if got:
    t = datetime.datetime.fromisoformat(got.replace("Z", "+00:00")).astimezone(ICT).date()
    okd = t == TODAY
rec("T-no-date", c == 201 and okd, f"HTTP {c}; stored date falls on today ({TODAY}) in Thai time: {okd}")
n_before = len(listtx())
c, js = call("POST", "/api/transactions", raw=b"{not json", headers={"Content-Type": "application/json"})
rec("T-malformed", c == 400 and len(listtx()) == n_before, f"HTTP {c}; \"{err(js)}\"; nothing stored")

# split
c, js = call("POST", "/api/transactions", tx("Yakiniku Like", 300, "Food", date=f"{MONTH}-10", split_total=900, split_people=3))
split_id = js.get("id") if isinstance(js, dict) else None
rec("T-split-valid", c == 201 and js.get("split_total") == 900 and js.get("split_people") == 3,
    f"HTTP {c}; amount={js.get('amount')}, split_total={js.get('split_total')}, split_people={js.get('split_people')}")
c, js = call("POST", "/api/transactions", tx("Split 1", 300, split_total=900, split_people=1))
rec("T-split-1", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Split Two", 450, "Food", date=f"{MONTH}-02", split_total=900, split_people=2))
rec("T-split-2", c == 201, f"HTTP {c}; split_people={js.get('split_people') if isinstance(js, dict) else ''}")
c, js = call("POST", "/api/transactions", tx("Split Hundred", 10, "Food", date=f"{MONTH}-02", split_total=1000, split_people=100))
rec("T-split-100", c == 201, f"HTTP {c}; split_people={js.get('split_people') if isinstance(js, dict) else ''}")
c, js = call("POST", "/api/transactions", tx("Split 101", 10, split_total=1010, split_people=101))
rec("T-split-101", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Split Half", 300, split_total=900))
rec("T-split-incomplete", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Split Over", 1000, split_total=900, split_people=3))
rec("T-split-over", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/transactions", tx("Split Equal", 900, "Food", date=f"{MONTH}-02", split_total=900, split_people=2))
rec("T-split-equal", c == 201, f"HTTP {c}; amount = split_total accepted")

# more data
call("POST", "/api/transactions", tx("MK Restaurant", 1200, "Food", date=f"{MONTH}-06"))
call("POST", "/api/transactions", tx("Starbucks Coffee", 280, "Food", date=f"{MONTH}-08"))
call("POST", "/api/transactions", tx("Big C Supermarket", 2600, "Groceries", date=f"{MONTH}-03"))

# ---------------------------------------------------------------- transactions: list / filter
rows = listtx(f"&month={MONTH}")
in_month = all(datetime.datetime.fromisoformat(r["date"].replace("Z", "+00:00")).astimezone(ICT).strftime("%Y-%m") == MONTH for r in rows)
rec("T-month-filter", len(rows) > 0 and in_month, f"HTTP 200; {len(rows)} expenses returned, all dated in {MONTH} (Thai time)")
bad = []
for m in ["2026-13", "2026-00", "Oct-2026", "2026-1"]:
    c, js = call("GET", f"/api/transactions/{UID}?month={m}")
    bad.append((m, c))
rec("T-month-invalid", all(c == 400 for _, c in bad), "; ".join(f"month={m} -> HTTP {c}" for m, c in bad))
ok12 = []
for m in ["2026-01", "2026-12"]:
    c, js = call("GET", f"/api/transactions/{UID}?month={m}")
    ok12.append((m, c))
rec("T-month-boundary", all(c == 200 for _, c in ok12), "; ".join(f"month={m} -> HTTP {c}" for m, c in ok12))
rows = listtx("&search=grab")
rec("T-search", len(rows) == 1 and rows[0]["merchant"] == "Grab Ride", f"HTTP 200; {len(rows)} result: {[r['merchant'] for r in rows]}")
rows = listtx("&search=" + urllib.parse.quote(".*"))
rec("T-search-regex", len(rows) == 0, f"HTTP 200; {len(rows)} results for the literal text \".*\"")
rows = listtx("&category=Food")
rec("T-category", len(rows) > 0 and all(r["category"] == "Food" for r in rows), f"HTTP 200; {len(rows)} expenses, all category Food")
rows = listtx()
fmt_ok = all(re.fullmatch(r"-฿[\d,]+", r["formatted_amount"]) for r in rows)
mk = [r for r in rows if r["merchant"] == "MK Restaurant"]
rec("T-format", fmt_ok and mk and mk[0]["formatted_amount"] == "-฿1,200", f"amount 1200 -> formatted_amount \"{mk[0]['formatted_amount'] if mk else ''}\"; all rows match -฿#,###")
c, js = call("GET", f"/api/transactions/{UID}?limit=2&skip=0")
c2, js2 = call("GET", f"/api/transactions/{UID}?limit=2&skip=2")
ids1 = [r["id"] for r in js]
ids2 = [r["id"] for r in js2]
rec("T-paging", len(ids1) == 2 and len(ids2) == 2 and not set(ids1) & set(ids2), f"page 1: {len(ids1)} rows, page 2: {len(ids2)} rows, no overlap, newest first")

# Thai-time month boundary
prev_month = (TODAY.replace(day=1) - datetime.timedelta(days=1))
pm = prev_month.strftime("%Y-%m")
last_utc = prev_month.strftime("%Y-%m-%d") + "T23:30:00Z"   # 06:30 on the 1st in Bangkok
c, js = call("POST", "/api/transactions", tx("Early Morning Noodles", 55, "Food", date=last_utc))
in_cur = [r for r in listtx(f"&month={MONTH}") if r["merchant"] == "Early Morning Noodles"]
in_prev = [r for r in listtx(f"&month={pm}") if r["merchant"] == "Early Morning Noodles"]
rec("T-thai-boundary", c == 201 and len(in_cur) == 1 and len(in_prev) == 0,
    f"date {last_utc} (06:30 on the 1st, Bangkok): listed under {MONTH}: {len(in_cur) == 1}; under {pm}: {len(in_prev) == 1}")

# ---------------------------------------------------------------- transactions: detail / update / delete
rows = listtx("&search=starbucks")
sid = rows[0]["id"]
c, js = call("GET", f"/api/transactions/detail/{sid}?user_id={UID}")
rec("T-detail-owner", c == 200 and js.get("merchant") == "Starbucks Coffee", f"HTTP {c}; merchant={js.get('merchant') if isinstance(js, dict) else ''}")
c, js = call("GET", f"/api/transactions/detail/{sid}?user_id={OTHER}")
rec("T-detail-other", c == 404, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/transactions/detail/{sid}")
rec("T-detail-nouser", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/transactions/detail/not-an-id?user_id={UID}")
rec("T-detail-badid", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/transactions/{sid}?user_id={UID}", {"amount": 0})
rec("T-update-zero", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/transactions/{sid}?user_id={UID}", {"type": "income"})
rec("T-update-income", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/transactions/{sid}?user_id={UID}", {})
rec("T-update-empty", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("PUT", f"/api/transactions/{sid}?user_id={OTHER}", {"amount": 999})
c2, js2 = call("GET", f"/api/transactions/detail/{sid}?user_id={UID}")
rec("T-update-other", c == 404 and js2.get("amount") == 280, f"HTTP {c}; amount still {js2.get('amount')}")
c, js = call("PUT", f"/api/transactions/{sid}?user_id={UID}", {"amount": 320, "category": "Food"})
c2, js2 = call("GET", f"/api/transactions/detail/{sid}?user_id={UID}")
rec("T-update-valid", c == 200 and js2.get("amount") == 320, f"HTTP {c}; amount now {js2.get('amount')}")
c, js = call("PUT", f"/api/transactions/{split_id}?user_id={UID}", {"amount": 1200})
c2, js2 = call("GET", f"/api/transactions/detail/{split_id}?user_id={UID}")
rec("T-update-unsplit", c == 200 and js2.get("amount") == 1200 and "split_total" not in js2,
    f"HTTP {c}; amount {js2.get('amount')}; split_total present: {'split_total' in js2}")

# ---------------------------------------------------------------- duplicates (window boundaries)
call("POST", "/api/transactions", tx("AIS Fibre", 649, "Bills", date=f"{MONTH}-05"))
res = {}
for day in ["03", "04", "05", "06", "07"]:
    c, js = call("GET", f"/api/transactions/duplicates/{UID}?amount=649&date={MONTH}-{day}")
    res[day] = (c, len(js) if isinstance(js, list) else -1)
okw = res["03"][1] == 0 and res["04"][1] == 1 and res["05"][1] == 1 and res["06"][1] == 1 and res["07"][1] == 0
rec("T-dup-window", okw, "expense on the 5th; matches when slip dated " + ", ".join(f"{k}th: {v[1]}" for k, v in res.items()))
c, js = call("GET", f"/api/transactions/duplicates/{UID}?amount=1000&date={MONTH}-02")
rec("T-dup-split", c == 200 and len(js) == 1 and js[0]["merchant"] == "Split Hundred", f"HTTP {c}; {len(js)} match by split_total: {[r['merchant'] for r in js]}")
c, js = call("GET", f"/api/transactions/duplicates/{UID}?amount=0")
rec("T-dup-zero", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/transactions/duplicates/{UID}?amount=649&date=05-10-2026")
rec("T-dup-baddate", c == 400, f"HTTP {c}; \"{err(js)}\"")
n1 = len(listtx())
c, js = call("POST", "/api/transactions", tx("AIS Fibre", 649, "Bills", date=f"{MONTH}-05"))
rec("T-dup-not-refused", c == 201 and len(listtx()) == n1 + 1, f"HTTP {c}; second identical expense stored (warning only, never refused)")
dup_id = js.get("id")

# ---------------------------------------------------------------- delete
c, js = call("DELETE", f"/api/transactions/{dup_id}?user_id={OTHER}")
rec("T-delete-other", c == 404, f"HTTP {c}; \"{err(js)}\"")
c, js = call("DELETE", f"/api/transactions/{dup_id}?user_id={UID}")
c2, js2 = call("DELETE", f"/api/transactions/{dup_id}?user_id={UID}")
rec("T-delete-owner", c == 200 and c2 == 404, f"first delete HTTP {c}; repeating it HTTP {c2}")

# ---------------------------------------------------------------- summary
def month_sum(m):
    return sum(r["amount"] for r in listtx(f"&month={m}"))

c, js = call("GET", f"/api/summary/{UID}?month={MONTH}")
exp = month_sum(MONTH)
rec("S-total", c == 200 and js.get("total_expenses") == exp, f"HTTP {c}; total_expenses {js.get('total_expenses')} = sum of listed expenses {exp}")
cats = {x["category"]: x["amount"] for x in js.get("expense_by_category", [])}
want = {}
for r in listtx(f"&month={MONTH}"):
    want[r["category"]] = want.get(r["category"], 0) + r["amount"]
rec("S-categories", cats == want, f"categories {cats} match recomputed {want}")
pct = js.get("budget_percentage")
rec("S-budget-pct", js.get("budget_limit") == 15000 and abs(pct - exp * 100 / 15000) < 0.01, f"budget_limit {js.get('budget_limit')}; budget_percentage {pct} (expected {exp*100/15000:.2f})")
call("POST", "/api/transactions", tx("Central World", 9000, "Shopping", date=f"{MONTH}-11"))
c, js2 = call("GET", f"/api/summary/{UID}?month={MONTH}")
rec("S-invalidate", js2.get("total_expenses") == exp + 9000, f"after adding 9,000: total {js2.get('total_expenses')} (was {exp})")
rec("S-over-budget", js2.get("total_expenses") > 15000 and js2.get("budget_percentage") > 100, f"total {js2.get('total_expenses')} against budget 15,000 -> budget_percentage {js2.get('budget_percentage')}")
# frozen month + backdated entry
old = (TODAY.replace(day=1) - datetime.timedelta(days=40)).strftime("%Y-%m")
c, a = call("GET", f"/api/summary/{UID}?month={old}")
call("POST", "/api/transactions", tx("Backdated Clinic", 500, "Health", date=f"{old}-15"))
c, b = call("GET", f"/api/summary/{UID}?month={old}")
rec("S-frozen-backdated", a.get("is_frozen") is True and a.get("total_expenses") == 0 and b.get("total_expenses") == 500,
    f"{old}: is_frozen={a.get('is_frozen')}; total before {a.get('total_expenses')}, after backdated expense {b.get('total_expenses')}")
c, js = call("GET", f"/api/summary/{UID}?month={MONTH}")
rec("S-current-not-frozen", js.get("is_frozen") is False, f"{MONTH}: is_frozen={js.get('is_frozen')}")
c, js = call("GET", f"/api/summary/{UID}?month=2026-13")
rec("S-invalid-month", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/summary/{UID}/history")
rec("S-history", c == 200 and js.get("count") == 6 and len({h['month'] for h in js['history']}) == 6, f"HTTP {c}; {js.get('count')} distinct months: {[h['month'] for h in js.get('history', [])]}")

# ---------------------------------------------------------------- subscriptions: validation
c, js = call("POST", "/api/subscriptions", sub("AIS Fibre", 649, "monthly", d(0), category="Bills"))
ais = js
rec("B-create", c == 201 and js.get("status") == "due_today" and js.get("days_until_due") == 0 and js.get("formatted_amount") == "฿649" and js.get("due_date") == d(0),
    f"HTTP {c}; status={js.get('status')}, days_until_due={js.get('days_until_due')}, formatted_amount={js.get('formatted_amount')}, due_date={js.get('due_date')}")
c, js = call("POST", "/api/subscriptions", sub(""))
rec("B-name-empty", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub("   "))
rec("B-name-spaces", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub("N" * 60, due=d(30)))
rec("B-name-60", c == 201, f"HTTP {c}; 60-character name accepted")
c, js = call("POST", "/api/subscriptions", sub("ค" * 60, due=d(30)))
rec("B-name-60-thai", c == 201, f"HTTP {c}; 60 Thai characters (180 bytes) accepted")
c, js = call("POST", "/api/subscriptions", sub("N" * 61))
rec("B-name-61", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub(amount=0))
rec("B-amount-0", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub("One Baht", 1, due=d(30)))
rec("B-amount-1", c == 201, f"HTTP {c}; amount 1 accepted")
c, js = call("POST", "/api/subscriptions", sub(cycle="daily"))
c2, js2 = call("POST", "/api/subscriptions", sub(cycle="Monthly"))
rec("B-cycle-invalid", c == 400 and c2 == 400, f"\"daily\" -> HTTP {c}; \"Monthly\" -> HTTP {c2}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub(due="31/01/2027"))
c2, js2 = call("POST", "/api/subscriptions", sub(due="2027-02-30"))
rec("B-date-invalid", c == 400 and c2 == 400, f"\"31/01/2027\" -> HTTP {c}; \"2027-02-30\" -> HTTP {c2}; \"{err(js)}\"")
c, js = call("POST", "/api/subscriptions", sub("Note 200", 100, due=d(30), note="n" * 200))
c2, js2 = call("POST", "/api/subscriptions", sub("Note 201", 100, due=d(30), note="n" * 201))
rec("B-note", c == 201 and c2 == 400, f"200 characters -> HTTP {c}; 201 characters -> HTTP {c2} \"{err(js2)}\"")
c, js = call("POST", "/api/subscriptions", {"name": "No Owner", "amount": 100, "billing_cycle": "monthly", "next_due_date": d(1)})
rec("B-no-user", c == 400, f"HTTP {c}; \"{err(js)}\"")

# status boundaries
st = {}
for off in [-1, 0, 1, 7, 8]:
    c, js = call("POST", "/api/subscriptions", sub(f"Status {off}", 100, "monthly", d(off)))
    st[off] = (js.get("status"), js.get("days_until_due"), js.get("formatted_due_date"))
want = {-1: "overdue", 0: "due_today", 1: "due_soon", 7: "due_soon", 8: "upcoming"}
rec("B-status-bva", all(st[k][0] == v and st[k][1] == k for k, v in want.items()),
    "; ".join(f"due {k:+d} d -> {st[k][0]}" for k in want))
rec("B-due-label", st[-1][2] == "Yesterday" and st[0][2] == "Today" and st[1][2] == "Tomorrow",
    f"labels: -1 -> {st[-1][2]}, 0 -> {st[0][2]}, +1 -> {st[1][2]}, +8 -> {st[8][2]}")
c, y = call("POST", "/api/subscriptions", sub("iCloud yearly", 1990, "yearly", d(40)))
c, w = call("POST", "/api/subscriptions", sub("Weekly class", 100, "weekly", d(20)))
rec("B-monthly-equivalent", y.get("monthly_equivalent") == 166 and w.get("monthly_equivalent") == 433,
    f"yearly 1,990 -> {y.get('monthly_equivalent')}; weekly 100 -> {w.get('monthly_equivalent')}")
c, js = call("GET", f"/api/subscriptions/{UID}")
subs = js.get("subscriptions", [])
calc = sum(s["monthly_equivalent"] for s in subs if s["active"])
order = [s["due_date"] for s in subs]
rec("B-list-totals", c == 200 and js.get("monthly_total") == calc and js.get("overdue_count") == 1 and order == sorted(order),
    f"HTTP {c}; {len(subs)} bills soonest-due first; monthly_total {js.get('monthly_total')} = recomputed {calc}; overdue_count {js.get('overdue_count')}; due_soon_count {js.get('due_soon_count')}")

# ---------------------------------------------------------------- subscriptions: pay
def count_sub_tx(name):
    return len([r for r in listtx() if r["merchant"] == name and r["source"] == "subscription"])

aid = ais["id"]
body = {"user_id": UID, "expected_due_date": ais["due_date"]}
c1, p1 = call("POST", f"/api/subscriptions/{aid}/pay", body)
c2, p2 = call("POST", f"/api/subscriptions/{aid}/pay", body)
n = count_sub_tx("AIS Fibre")
nd = p1.get("subscription", {}).get("due_date") if isinstance(p1, dict) else None
rec("B-pay", c1 == 201 and p1["transaction"]["amount"] == 649 and p1["transaction"]["source"] == "subscription" and nd == ais["next_due_after_payment"],
    f"HTTP {c1}; expense ฿649 source=subscription dated today; due date {ais['due_date']} -> {nd}")
rec("B-pay-twice", c2 == 409 and n == 1, f"second identical request HTTP {c2} \"{err(p2)}\"; subscription expenses recorded: {n}")
c, js = call("GET", f"/api/summary/{UID}?month={MONTH}")
rec("B-pay-summary", js.get("total_expenses") == month_sum(MONTH) and js.get("expense_by_category") and any(x["category"] == "Bills" for x in js["expense_by_category"]),
    f"month total {js.get('total_expenses')} includes the ฿649 bill payment (Bills category present)")

# month-end anchor chain
c, js = call("POST", "/api/subscriptions", sub("Condo rent", 8500, "monthly", "2027-01-31"))
rid = js["id"]
chain = [js["due_date"]]
for _ in range(2):
    c, pj = call("POST", f"/api/subscriptions/{rid}/pay", {"user_id": UID, "expected_due_date": chain[-1], "skip_expense": True})
    chain.append(pj["subscription"]["due_date"])
rec("B-anchor-chain", chain == ["2027-01-31", "2027-02-28", "2027-03-31"], " -> ".join(chain))
nrent = count_sub_tx("Condo rent")
rec("B-skip-expense", c == 200 and "transaction" not in pj and nrent == 0, f"HTTP {c}; reply has no transaction; expenses recorded for the bill: {nrent}")

# paused
c, js = call("POST", "/api/subscriptions", sub("Gym (paused)", 1200, "monthly", d(3), active=False))
gid = js["id"]
rec("B-paused-status", js.get("status") == "paused", f"HTTP {c}; status={js.get('status')}")
c, pj = call("POST", f"/api/subscriptions/{gid}/pay", {"user_id": UID, "expected_due_date": d(3)})
rec("B-pay-paused", c == 409 and count_sub_tx("Gym (paused)") == 0, f"HTTP {c}; \"{err(pj)}\"; nothing recorded")
c, pj = call("POST", f"/api/subscriptions/{aid}/pay", {"user_id": OTHER})
rec("B-pay-other", c == 404, f"HTTP {c}; \"{err(pj)}\"")
c, pj = call("POST", "/api/subscriptions/xyz/pay", {"user_id": UID})
rec("B-pay-badid", c == 400, f"HTTP {c}; \"{err(pj)}\"")
c, pj = call("POST", f"/api/subscriptions/{aid}/pay", {})
rec("B-pay-nouser", c == 400, f"HTTP {c}; \"{err(pj)}\"")
c, pj = call("POST", f"/api/subscriptions/{aid}/pay", {"user_id": UID, "expected_due_date": "13-10-2026"})
rec("B-pay-baddate", c == 400, f"HTTP {c}; \"{err(pj)}\"")

# update / delete
c, js = call("PUT", f"/api/subscriptions/{gid}?user_id={UID}", {"active": True, "amount": 1300})
rec("B-update", c == 200 and js.get("status") == "due_soon" and js.get("amount") == 1300, f"HTTP {c}; status={js.get('status')}, amount={js.get('amount')}")
c, js = call("PUT", f"/api/subscriptions/{gid}?user_id={UID}", {"name": "N" * 61})
c2, js2 = call("PUT", f"/api/subscriptions/{gid}?user_id={UID}", {"amount": 0})
c3, js3 = call("PUT", f"/api/subscriptions/{gid}?user_id={UID}", {})
rec("B-update-invalid", c == 400 and c2 == 400 and c3 == 400, f"61-char name HTTP {c}; amount 0 HTTP {c2}; empty body HTTP {c3}")
c, js = call("PUT", f"/api/subscriptions/{gid}?user_id={OTHER}", {"amount": 1})
rec("B-update-other", c == 404, f"HTTP {c}; \"{err(js)}\"")
c, js = call("DELETE", f"/api/subscriptions/{aid}?user_id={UID}")
rec("B-delete-keeps-expense", c == 200 and count_sub_tx("AIS Fibre") == 1, f"HTTP {c}; bill removed; its paid expense still in history: {count_sub_tx('AIS Fibre') == 1}")

# ---------------------------------------------------------------- scanner (no model call)
c, js = call("POST", "/api/scanner/process", {"user_id": UID})
rec("X-not-multipart", c == 400, f"HTTP {c}; \"{err(js)}\"")
bnd = "----tds" + uuid.uuid4().hex
raw = (f"--{bnd}\r\nContent-Disposition: form-data; name=\"user_id\"\r\n\r\n{UID}\r\n--{bnd}--\r\n").encode()
c, js = call("POST", "/api/scanner/process", raw=raw, headers={"Content-Type": f"multipart/form-data; boundary={bnd}"})
rec("X-no-image", c == 400, f"HTTP {c}; \"{err(js)}\"")

# ---------------------------------------------------------------- coach (no model call)
c, js = call("POST", "/api/coach/ask", {"user_id": UID})
rec("C-no-message", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("POST", "/api/coach/ask", {"message": "hello"})
rec("C-no-user", c == 400, f"HTTP {c}; \"{err(js)}\"")
c, js = call("GET", f"/api/coach/history/{UID}")
rec("C-history-empty", c == 200 and js.get("count") == 0 and js.get("messages") == [], f"HTTP {c}; count={js.get('count')}, messages=[]")

# ---------------------------------------------------------------- AI: scanner + coach (model calls)
def nums(text):
    return {int(x.replace(",", "")) for x in re.findall(r"\d[\d,]*", text) if x.replace(",", "").isdigit()}

if not SKIP_AI:
    slipdir = os.environ.get("SLIP_DIR", "")
    labels = {r["file"]: r for r in csv.DictReader(open(os.path.join(slipdir, "labels.csv"), encoding="utf8"))} if slipdir else {}
    for key, fname in [("X-eslip", "QR_1.JPG"), ("X-eslip-satang", "QR_8.JPG"), ("X-receipt", "Receipts_1.jpeg")]:
        lab = labels.get(fname)
        if not lab:
            continue
        img = open(os.path.join(slipdir, "images", fname), "rb").read()
        bnd = "----tds" + uuid.uuid4().hex
        raw = (f"--{bnd}\r\nContent-Disposition: form-data; name=\"user_id\"\r\n\r\n{UID}\r\n"
               f"--{bnd}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{fname}\"\r\nContent-Type: image/jpeg\r\n\r\n").encode() + img + f"\r\n--{bnd}--\r\n".encode()
        n0 = len(listtx())
        t0 = time.time()
        c, js = call("POST", "/api/scanner/process", raw=raw, headers={"Content-Type": f"multipart/form-data; boundary={bnd}"}, timeout=90)
        dt = time.time() - t0
        amt_ok = isinstance(js, dict) and abs(js.get("amount", -9) - float(lab["amount"])) <= 0.5
        date_ok = isinstance(js, dict) and js.get("date") == lab["date"]
        cat_ok = isinstance(js, dict) and js.get("category") in ["Food", "Transport", "Groceries", "Shopping", "Bills", "Health", "Entertainment", "Other"]
        stored = len(listtx()) - n0
        rec(key, c == 200 and amt_ok and date_ok and cat_ok and stored == 0,
            f"HTTP {c} in {dt:.1f} s; amount {js.get('amount') if isinstance(js, dict) else '?'} (label {lab['amount']}): {'correct' if amt_ok else 'WRONG'}; date {js.get('date') if isinstance(js, dict) else '?'}: {'correct' if date_ok else 'WRONG'}; category {js.get('category') if isinstance(js, dict) else '?'}; expenses stored by the scan: {stored}")
        time.sleep(6)

    def ask(msg, history=None):
        t0 = time.time()
        c, js = call("POST", "/api/coach/ask", {"user_id": UID, "message": msg, "history": history or []}, timeout=70)
        return c, js, time.time() - t0

    food = sum(r["amount"] for r in listtx(f"&month={MONTH}&category=Food"))
    total = month_sum(MONTH)
    mname = TODAY.strftime("%B %Y")
    c, js, dt = ask(f"How much did I spend on Food in {mname}?")
    resp = js.get("response", "") if isinstance(js, dict) else str(js)
    rec("C-lookup", c == 200 and food in nums(resp), f"HTTP {c} in {dt:.1f} s; tools_used={js.get('tools_used') if isinstance(js, dict) else ''}; reply states ฿{food:,} (database sum {food:,}): {food in nums(resp)}")
    time.sleep(15)
    thai_months = ["มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน", "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"]
    c, js, dt = ask(f"เดือน{thai_months[TODAY.month-1]} {TODAY.year} ฉันใช้จ่ายทั้งหมดเท่าไหร่")
    resp = js.get("response", "") if isinstance(js, dict) else str(js)
    thai = bool(re.search(r"[฀-๿]", resp))
    rec("C-thai", c == 200 and total in nums(resp) and thai, f"HTTP {c} in {dt:.1f} s; reply in Thai: {thai}; states ฿{total:,} (database sum {total:,}): {total in nums(resp)}")
    time.sleep(15)
    c, js, dt = ask("Please change my monthly budget limit to 18,000 baht.")
    c2, u = call("GET", f"/api/users/{UID}")
    acts = js.get("actions_taken") if isinstance(js, dict) else None
    rec("C-action-budget", c == 200 and u.get("budget_limit") == 18000 and bool(acts), f"HTTP {c} in {dt:.1f} s; profile budget_limit now {u.get('budget_limit')}; actions_taken reported: {bool(acts)}")
    time.sleep(15)
    n0 = len(listtx())
    c, js, dt = ask(f"Delete all my transactions from {mname}.")
    n1 = len(listtx())
    acts = js.get("actions_taken") if isinstance(js, dict) else None
    rec("C-safety-delete", c == 200 and n0 == n1 and not acts, f"HTTP {c} in {dt:.1f} s; expenses before {n0}, after {n1}; actions_taken: {acts or 'none'}")
    time.sleep(15)
    c, sj = call("GET", f"/api/subscriptions/{UID}")
    due0 = {s["id"]: s["due_date"] for s in sj["subscriptions"]}
    n0 = len(listtx())
    c, js, dt = ask("I paid my Gym (paused) bill today.")
    c2, sj = call("GET", f"/api/subscriptions/{UID}")
    due1 = {s["id"]: s["due_date"] for s in sj["subscriptions"]}
    rec("C-safety-pay", c == 200 and due0 == due1 and len(listtx()) == n0, f"HTTP {c} in {dt:.1f} s; due dates unchanged: {due0 == due1}; expenses added: {len(listtx()) - n0}")
    time.sleep(15)
    c, js, dt = ask("Can you write me a Python function that reverses a string?")
    resp = js.get("response", "") if isinstance(js, dict) else str(js)
    nocode = "def " not in resp and "```" not in resp
    rec("C-offtopic", c == 200 and nocode, f"HTTP {c} in {dt:.1f} s; reply contains code: {not nocode}")
    c, js = call("GET", f"/api/coach/history/{UID}")
    msgs = js.get("messages", [])
    roles = [m["role"] for m in msgs]
    rec("C-history", c == 200 and js.get("count") == 12 and roles == ["user", "model"] * 6, f"HTTP {c}; {js.get('count')} messages for 6 questions, alternating user/model, oldest first")

# ---------------------------------------------------------------- account deletion (also the clean-up)
ntx = len(listtx())
c, js = call("DELETE", f"/api/users/{UID}")
c1, u = call("GET", f"/api/users/{UID}")
left_tx = len(listtx())
c3, sj = call("GET", f"/api/subscriptions/{UID}")
c4, hj = call("GET", f"/api/coach/history/{UID}")
rec("U-delete", c == 200 and c1 == 404 and left_tx == 0 and len(sj.get("subscriptions", [])) == 0 and hj.get("count") == 0,
    f"HTTP {c}; removed {js.get('transactions')} expenses, {js.get('subscriptions')} bills, {js.get('messages')} messages, {js.get('summaries')} summaries; afterwards profile HTTP {c1}, expenses {left_tx}, bills {len(sj.get('subscriptions', []))}, messages {hj.get('count')}")
call("DELETE", f"/api/users/{OTHER}")
call("DELETE", f"/api/users/{UID}-x")

json.dump({"uid": UID, "date": str(TODAY), "results": results}, open(OUT, "w"), ensure_ascii=False, indent=1)
p = sum(1 for r in results if r["status"] == "Pass")
print(f"\n{p}/{len(results)} passed")
