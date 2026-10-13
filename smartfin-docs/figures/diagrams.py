"""Draws every figure for the SmartFin Chapter 1-5 report as PNG files."""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Ellipse, FancyArrowPatch, Rectangle, Circle

OUT = os.path.join(os.path.dirname(__file__), "fig")
os.makedirs(OUT, exist_ok=True)
plt.rcParams.update({"font.family": ["Times New Roman", "Tahoma"],
                     "font.size": 10})

INK = "#1f2933"
MUTED = "#52606d"
ACCENT = "#c2410c"      # SmartFin orange, darkened for print
FILL = "#fff7ed"
FILL2 = "#f1f5f9"
FILL3 = "#ecfdf5"


def canvas(w, h):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, w * 10)
    ax.set_ylim(0, h * 10)
    ax.axis("off")
    return fig, ax


def box(ax, x, y, w, h, text, fc=FILL2, ec=INK, fs=9.5, bold=False, rounded=True, lw=1.0, ls="-", color=INK):
    style = "round,pad=0.02,rounding_size=1.2" if rounded else "square,pad=0.0"
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=style, fc=fc, ec=ec, lw=lw, ls=ls))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs,
            fontweight="bold" if bold else "normal", color=color, linespacing=1.25)


def arrow(ax, p, q, text=None, color=INK, style="-|>", ls="-", fs=8.5, off=(0, 1.2), rad=0.0, lw=1.0):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle=style, mutation_scale=11, color=color, lw=lw,
                                 linestyle=ls, connectionstyle=f"arc3,rad={rad}", shrinkA=2, shrinkB=2))
    if text:
        mx, my = (p[0] + q[0]) / 2 + off[0], (p[1] + q[1]) / 2 + off[1]
        ax.text(mx, my, text, ha="center", va="center", fontsize=fs, color=MUTED,
                bbox=dict(fc="white", ec="none", pad=0.6))


def save(fig, name):
    fig.savefig(os.path.join(OUT, name), dpi=200, bbox_inches="tight", pad_inches=0.08, facecolor="white")
    plt.close(fig)


# ---------------------------------------------------------------- 2.1 fishbone
def fishbone():
    fig, ax = canvas(10, 5.2)
    spine_y = 26
    ax.plot([6, 78], [spine_y, spine_y], color=INK, lw=2)
    box(ax, 78, spine_y - 7, 21, 14,
        "Expenses go\nunrecorded, and\nadvice is not based\non the user's data", fc=FILL, ec=ACCENT, fs=9.5, bold=True)
    bones = [
        ("PEOPLE", 16, True, ["Forget small daily payments", "Abandon manual entry within weeks",
                             "Limited financial literacy"]),
        ("PROCESS", 46, True, ["Every expense must be typed", "Slips kept as images, never entered",
                              "Recurring bills produce no slip"]),
        ("TECHNOLOGY", 16, False, ["No consumer open-banking API in Thailand", "Generic OCR misreads Thai script",
                                  "Chatbots cannot see the user's records"]),
        ("DATA", 46, False, ["Buddhist-era years (2569) on slips", "Satang decimals and ฿ symbols",
                            "Layout differs for every bank"]),
    ]
    for label, x0, top, causes in bones:
        y_end = 48 if top else 4
        x_end = x0 + 26
        ax.plot([x0, x_end], [y_end, spine_y], color=INK, lw=1.4)
        ax.text(x0 - 1, y_end + (1.8 if top else -1.8), label, ha="left", va="center", fontsize=10.5,
                fontweight="bold", color=ACCENT)
        for i, c in enumerate(causes):
            t = (i + 1) / (len(causes) + 1)
            bx = x0 + (x_end - x0) * t
            by = y_end + (spine_y - y_end) * t
            ax.plot([bx - 4, bx], [by, by], color=MUTED, lw=0.9)
            ax.text(bx - 4.5, by, c, ha="right", va="center", fontsize=8.6, color=INK)
    save(fig, "fig2_1_fishbone.png")


# ---------------------------------------------------------------- 2.2 gantt
def gantt():
    months = ["Dec 25", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec 26"]
    # (task, start month index, end month index inclusive-ish as float, phase)
    tasks = [
        ("Concept and proposal", 0, 1.6, "p1"),
        ("Feasibility study (Ch. 1-2)", 1.5, 2.9, "p1"),
        ("Analysis and design (Ch. 3)", 3.0, 6.4, "p1"),
        ("UI/UX design and prototype", 2.0, 4.8, "p1"),
        ("Database design and setup", 2.7, 3.6, "p1"),
        ("Backend API (Go/Fiber)", 4.0, 8.9, "p2"),
        ("Flutter client", 4.0, 9.4, "p2"),
        ("Slip scanner + Auto-Detect", 5.0, 9.4, "p2"),
        ("Agentic AI Coach", 6.8, 9.4, "p2"),
        ("Subscriptions and bill reminders", 8.4, 9.45, "p2"),
        ("Ground-truth evaluation", 8.4, 10.6, "p3"),
        ("Spending-only refactor", 9.4, 9.95, "p2"),
        ("Testing and deployment", 9.45, 11.5, "p3"),
        ("Chapter 4-5 and final report", 9.45, 12.6, "p4"),
    ]
    colours = {"p1": "#94a3b8", "p2": ACCENT, "p3": "#0d9488", "p4": "#6d28d9"}
    fig, ax = plt.subplots(figsize=(10, 5.0))
    for i, (name, s, e, p) in enumerate(tasks):
        ax.barh(i, e - s, left=s, height=0.55, color=colours[p], edgecolor="none")
    ax.set_yticks(range(len(tasks)))
    ax.set_yticklabels([t[0] for t in tasks], fontsize=9)
    ax.invert_yaxis()
    ax.set_xticks([i + 0.5 for i in range(len(months))])
    ax.set_xticklabels(months, fontsize=8.5)
    ax.set_xlim(0, len(months))
    for i in range(len(months) + 1):
        ax.axvline(i, color="#e5e7eb", lw=0.6, zorder=0)
    milestones = [(1.5, "Proposal"), (2.55, "Feasibility"), (5.7, "Design"), (9.45, "Alpha"),
                  (10.5, "Beta"), (11.5, "D-Day"), (12.6, "Final")]
    for x, lab in milestones:
        ax.axvline(x, color=INK, lw=0.8, ls=(0, (3, 2)))
        ax.text(x, -1.05, lab, rotation=0, ha="center", va="bottom", fontsize=8, color=INK,
                bbox=dict(fc="white", ec="none", pad=0.4))
    ax.axvspan(6.4, 7.2, color="#f3f4f6", zorder=-1)
    ax.text(6.8, 1.0, "term\nbreak", ha="center", fontsize=8, color=MUTED)
    for s in ["top", "right", "left"]:
        ax.spines[s].set_visible(False)
    ax.tick_params(axis="y", length=0)
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(color=colours["p1"], label="CSC498 analysis and design"),
                       Patch(color=colours["p2"], label="Implementation"),
                       Patch(color=colours["p3"], label="Evaluation and testing"),
                       Patch(color=colours["p4"], label="Documentation")],
              loc="upper center", bbox_to_anchor=(0.45, -0.07), fontsize=8.5, frameon=False, ncol=4)
    ax.set_ylim(len(tasks) - 0.4, -1.4)
    save(fig, "fig2_2_gantt.png")


# ---------------------------------------------------------------- 2.3 PERT
def pert():
    fig, ax = canvas(10, 4.6)
    nodes = {
        "A": (8, 23, "A\nProposal\n4 wk"),
        "B": (21.5, 23, "B\nFeasibility\n6 wk"),
        "C": (34, 36, "C\nUI/UX design\n8 wk"),
        "D": (34, 10, "D\nDB design\n4 wk"),
        "E": (48, 23, "E\nAnalysis &\ndesign 10 wk"),
        "F": (62, 36, "F\nBackend API\n8 wk"),
        "G": (62, 10, "G\nFlutter client\n9 wk"),
        "H": (76, 36, "H\nScanner +\nCoach 6 wk"),
        "I": (76, 10, "I\nBills +\nreminders 2 wk"),
        "J": (88, 23, "J\nEvaluation +\ntesting 6 wk"),
    }
    for k, (x, y, t) in nodes.items():
        crit = k in "ABEFHJ"
        ax.add_patch(Circle((x, y), 6.1, fc=FILL if crit else FILL2, ec=ACCENT if crit else INK,
                            lw=1.6 if crit else 1.0))
        ax.text(x, y, t, ha="center", va="center", fontsize=8.2)
    edges = ["AB", "BC", "BD", "CE", "DE", "EF", "EG", "FH", "GI", "HJ", "IJ", "GH"]
    import math
    for a, b in edges:
        (x1, y1, _), (x2, y2, _) = nodes[a], nodes[b]
        d = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / d, (y2 - y1) / d
        crit = a + b in ("AB", "BC", "CE", "EF", "FH", "HJ")
        arrow(ax, (x1 + ux * 6.2, y1 + uy * 6.2), (x2 - ux * 6.2, y2 - uy * 6.2),
              color=ACCENT if crit else INK, lw=1.6 if crit else 1.0)
    ax.text(50, 2, "Critical path (orange): A → B → C → E → F → H → J  ≈ 48 weeks of project time",
            ha="center", fontsize=9, color=ACCENT)
    save(fig, "fig2_3_pert.png")


# ---------------------------------------------------------------- 3.1 existing workflow
def existing_flow():
    fig, ax = canvas(10, 2.6)
    steps = ["Pay by PromptPay\nor QR", "Bank app saves\nan e-slip image", "User must open a\nbudgeting app",
             "Type merchant,\namount, date,\ncategory", "Static chart\nof past spending", "No answer to\n\"can I afford it?\""]
    w, gap = 13.5, 3.0
    for i, s in enumerate(steps):
        x = 1 + i * (w + gap)
        fc = FILL if i in (3, 5) else FILL2
        ec = ACCENT if i in (3, 5) else INK
        box(ax, x, 7, w, 12, s, fc=fc, ec=ec, fs=9)
        if i:
            arrow(ax, (x - gap, 13), (x, 13))
    ax.text(1 + 3 * (w + gap) + w / 2, 3.2, "step abandoned within weeks", ha="center", fontsize=8.5,
            color=ACCENT, style="italic")
    ax.text(1 + 5 * (w + gap) + w / 2, 3.2, "advice is generic", ha="center", fontsize=8.5, color=ACCENT,
            style="italic")
    save(fig, "fig3_1_existing.png")


# ---------------------------------------------------------------- 3.2 use case
def stick(ax, x, y, label):
    ax.add_patch(Circle((x, y + 7), 1.6, fc="white", ec=INK, lw=1.2))
    ax.plot([x, x], [y + 5.4, y + 0.5], color=INK, lw=1.2)
    ax.plot([x - 3, x + 3], [y + 4, y + 4], color=INK, lw=1.2)
    ax.plot([x, x - 2.5], [y + 0.5, y - 3.5], color=INK, lw=1.2)
    ax.plot([x, x + 2.5], [y + 0.5, y - 3.5], color=INK, lw=1.2)
    ax.text(x, y - 6, label, ha="center", va="top", fontsize=9.5, fontweight="bold")


def use_case():
    fig, ax = canvas(10, 7.2)
    ax.add_patch(Rectangle((20, 3), 56, 66, fc="white", ec=INK, lw=1.2))
    ax.text(48, 66.5, "SmartFin", ha="center", fontsize=11, fontweight="bold")
    cases = [
        ("Sign up / sign in", 60, False), ("Scan a payment slip", 52, True), ("Auto-Detect a new slip", 44, True),
        ("Review and confirm entry", 36, True), ("Track spending and budget", 28, False),
        ("Ask the AI Coach", 20, True), ("Track bills and get reminded", 12, False),
        ("Manage profile and account", 5.5, False),
    ]
    pos = {}
    for name, y, hl in cases:
        ax.add_patch(Ellipse((48, y), 34, 6.2, fc=FILL if hl else FILL2, ec=ACCENT if hl else INK,
                             lw=1.4 if hl else 1.0))
        ax.text(48, y, name, ha="center", va="center", fontsize=9.3)
        pos[name] = y
    stick(ax, 8, 34, "Thai user")
    for name, y, _ in cases:
        ax.plot([11, 31], [36, y], color=MUTED, lw=0.8)
    # externals
    box(ax, 83, 45, 15, 9, "Gemini 3.5\nFlash-Lite", fc=FILL3, fs=9)
    box(ax, 83, 56, 15, 8, "Firebase\nAuth", fc=FILL3, fs=9)
    box(ax, 83, 7, 15, 9, "Device\nnotifications", fc=FILL3, fs=9)
    ax.text(90.5, 67, "external systems", ha="center", fontsize=8.5, color=MUTED, style="italic")
    for y in (52, 44, 20):
        ax.plot([65, 83], [y, 49.5], color=MUTED, lw=0.8, ls="--")
    ax.plot([65, 83], [60, 60], color=MUTED, lw=0.8, ls="--")
    ax.plot([65, 83], [12, 11.5], color=MUTED, lw=0.8, ls="--")
    ax.text(48, -0.8, "«include»: Scan a payment slip and Auto-Detect a new slip both include Review and confirm entry",
            ha="center", fontsize=8.3, color=MUTED, style="italic")
    save(fig, "fig3_2_usecase.png")


# ---------------------------------------------------------------- 3.3 architecture
def architecture():
    fig, ax = canvas(10, 6.2)
    tiers = [(1, "CLIENT", "#f8fafc", 29), (33, "API (Go)", "#fff7ed", 32), (68, "DATA AND AI SERVICES", "#f0fdf4", 31)]
    for x, lab, fc, w in tiers:
        ax.add_patch(FancyBboxPatch((x, 2), w, 58, boxstyle="round,pad=0,rounding_size=1.5", fc=fc, ec="#cbd5e1"))
        ax.text(x + w / 2, 57, lab, ha="center", fontsize=9, color=MUTED, fontweight="bold")
    box(ax, 3, 40, 25, 14, "Flutter app (Dart)\n16 screens · go_router\nsetState · Dio (60 s)", fc="white", fs=9)
    box(ax, 3, 27, 25, 10, "Auto-Detect\nphoto_manager watcher", fc="white", fs=9)
    box(ax, 3, 14, 25, 10, "Bill reminders\nlocal notifications, 09:00", fc="white", fs=9)
    box(ax, 3, 4, 25, 7, "Firebase Authentication\n(sign-in on device)", fc="white", fs=8.6)
    box(ax, 35, 44, 28, 10, "Fiber v2 REST API\n24 endpoints under /api", fc="white", fs=9, bold=True)
    box(ax, 35, 33, 13, 8, "CRUD handlers\ntx · bills · users", fc="white", fs=8.3)
    box(ax, 50, 33, 13, 8, "Scanner\n(stateless)", fc="white", fs=8.5)
    box(ax, 35, 13, 28, 17, "", fc="white", ec=ACCENT, lw=1.3)
    ax.text(49, 27.3, "Coach orchestrator", ha="center", fontsize=9, fontweight="bold", color=ACCENT)
    ax.text(49, 24.6, "≤ 5 turns · 45 s budget · 7 tools", ha="center", fontsize=8.3, color=INK)
    for i, (t, sub) in enumerate([("Retrieval", "4 tools"), ("Action", "2 tools"), ("Research", "1 tool")]):
        box(ax, 36 + i * 9, 14.5, 8.2, 7, f"{t}\n{sub}", fc=FILL, ec=ACCENT, fs=7.8)
    box(ax, 35, 4, 28, 7, "internal/summaries\nmonth windows at +07:00", fc="white", fs=8.3)
    box(ax, 70, 38, 27, 16, "MongoDB Atlas\nusers · transactions\nmonthly_summaries\nchat_messages · subscriptions\nGridFS avatars",
        fc="white", fs=8.6)
    box(ax, 70, 18, 27, 14, "Google Gemini 3.5 Flash-Lite\nvision extraction\nfunction calling", fc="white", fs=8.8)
    box(ax, 70, 5, 27, 9, "Web search\nSerpAPI → DuckDuckGo", fc="white", fs=8.6)
    arrow(ax, (28, 48), (35, 49), "HTTPS\nJSON", off=(0, 4))
    arrow(ax, (63, 49), (70, 47), "reads / writes", off=(0, 2.5))
    arrow(ax, (63, 35), (70, 29), None)
    arrow(ax, (63, 22), (70, 24), None)
    arrow(ax, (63, 16), (70, 10), None)
    ax.text(66.5, 31.5, "image", fontsize=7.5, color=MUTED, ha="center")
    ax.text(66.5, 25.5, "tools", fontsize=7.5, color=MUTED, ha="center")
    save(fig, "fig3_3_architecture.png")


# ---------------------------------------------------------------- 3.4 ERD
def erd():
    fig, ax = canvas(10, 7.0)

    def entity(x, y, title, rows, w=27):
        h = 4.2 + 3.1 * len(rows)
        ax.add_patch(Rectangle((x, y - h), w, h, fc="white", ec=INK, lw=1.1))
        ax.add_patch(Rectangle((x, y - 4.2), w, 4.2, fc=FILL, ec=INK, lw=1.1))
        ax.text(x + w / 2, y - 2.1, title, ha="center", va="center", fontsize=9.5, fontweight="bold")
        for i, r in enumerate(rows):
            ax.text(x + 1.2, y - 6.0 - i * 3.1, r, ha="left", va="center", fontsize=7.9, family="monospace")

    entity(36, 69, "users", ["PK firebase_uid  string", "   name, email", "   photo_url", "   current_status",
                              "   financial_health", "   budget_limit   int64", "   created_at, updated_at"])
    entity(2, 47, "transactions", ["PK _id           ObjectID", "FK user_id       string", "   merchant, category",
                                    "   amount        int64 ฿", "   type = expense, source", "   split_total, split_people", "   date, created_at"])
    entity(70, 47, "subscriptions", ["PK _id          ObjectID", "FK user_id      string", "   name, category, note",
                                      "   amount       int64 ฿", "   billing_cycle", "   next_due_date, anchor_day",
                                      "   active, last_paid_at"])
    entity(2, 17, "monthly_summaries (derived)", ["   user_id + month", "   total_expenses, budget_limit",
                                                   "   expense_by_category[]", "   is_frozen"], w=33)
    entity(42, 27, "chat_messages", ["PK _id        ObjectID", "FK user_id    string", "   role, content",
                                      "   tool_calls[], actions[]", "   created_at"])

    def rel(p, q):
        ax.plot([p[0], q[0]], [p[1], q[1]], color=INK, lw=1)
        ax.text(p[0] + 1.5, p[1] - 3.0 if p[1] < 50 else p[1] + 1.2, "1", fontsize=9, color=ACCENT, ha="center")
        ax.text(q[0] + 1.5, q[1] + 1.2, "N", fontsize=9, color=ACCENT)

    rel((36, 55), (29, 45))
    rel((63, 55), (70, 45))
    rel((55, 43.1), (55, 27))
    rel((40, 43.1), (33, 17))
    ax.text(84, 12, "monthly_summaries is a derived cache,\nrebuilt from transactions.\nAll collections are keyed by the\nFirebase UID string; integrity is\nenforced by the API, not MongoDB.",
            fontsize=8, color=MUTED, style="italic", ha="center", va="center")
    save(fig, "fig3_4_erd.png")


# ---------------------------------------------------------------- 3.5 context DFD
def dfd_context():
    fig, ax = canvas(10, 4.6)
    ax.add_patch(Circle((52, 25), 11, fc=FILL, ec=ACCENT, lw=1.5))
    ax.text(52, 25, "0\nSmartFin\nsystem", ha="center", va="center", fontsize=10, fontweight="bold")
    box(ax, 2, 20, 18, 12, "Thai user", fc=FILL2, rounded=False, fs=10, bold=True)
    box(ax, 2, 2, 18, 9, "Firebase Auth", fc=FILL2, rounded=False, fs=9.5, bold=True)
    box(ax, 81, 31, 17, 10, "Gemini 3.5\nFlash-Lite", fc=FILL2, rounded=False, fs=9.5, bold=True)
    box(ax, 81, 9, 17, 10, "Web search", fc=FILL2, rounded=False, fs=9.5, bold=True)
    arrow(ax, (20, 29.5), (41.3, 29.5), "slip image, question,\nbills, budget", off=(0, 3.8))
    arrow(ax, (41.3, 22.5), (20, 22.5), "expenses, summary,\nanswers, reminders", off=(0, -3.8))
    arrow(ax, (8, 20), (8, 11), "credentials", off=(-5, 0))
    arrow(ax, (20, 7), (44, 17), "Firebase UID", off=(2, -3))
    arrow(ax, (62, 30), (81, 38), "image, prompt,\ntool results", off=(-3, 4))
    arrow(ax, (81, 33), (63, 27), "fields (JSON),\ntool calls, text", off=(4, -3.5))
    arrow(ax, (62, 20), (81, 15), "query", off=(0, 2))
    arrow(ax, (81, 12), (61, 17), "results", off=(0, -2.5))
    save(fig, "fig3_5_dfd_context.png")


# ---------------------------------------------------------------- 3.6 / 3.7 level-1 DFDs
def dfd_store(ax, x, y, w, label, code):
    ax.plot([x, x + w], [y + 5, y + 5], color=INK, lw=1)
    ax.plot([x, x + w], [y, y], color=INK, lw=1)
    ax.plot([x, x], [y, y + 5], color=INK, lw=1)
    ax.plot([x + 5, x + 5], [y, y + 5], color=INK, lw=1)
    ax.text(x + 2.5, y + 2.5, code, ha="center", va="center", fontsize=8.5)
    ax.text(x + 5 + (w - 5) / 2, y + 2.5, label, ha="center", va="center", fontsize=8.8)


def proc(ax, x, y, text, r=7.2):
    ax.add_patch(Circle((x, y), r, fc=FILL, ec=ACCENT, lw=1.2))
    ax.text(x, y, text, ha="center", va="center", fontsize=8.4)


def dfd_scan():
    fig, ax = canvas(10, 5.0)
    box(ax, 1, 18, 13, 10, "Thai user", rounded=False, fs=9.5, bold=True)
    proc(ax, 26, 32, "1.1\nCapture or\ndetect slip")
    proc(ax, 50, 32, "1.2\nExtract\nfields")
    proc(ax, 74, 32, "1.3\nVerify and\nconfirm")
    proc(ax, 74, 10, "1.4\nSave\nexpense")
    box(ax, 40, 4, 20, 8, "Gemini Vision", rounded=False, fs=9, bold=True)
    dfd_store(ax, 84, 20, 15, "transactions", "D2")
    dfd_store(ax, 84, 2, 15, "processed ids", "L1")
    arrow(ax, (14, 26), (19.5, 30), "photo / new\ngallery image", off=(-5, 5))
    arrow(ax, (33.2, 32), (42.8, 32), "image", off=(0, 2.4))
    arrow(ax, (48, 24.8), (48, 12), "image + prompt", off=(-7, 0))
    arrow(ax, (52, 12), (52, 24.8), "JSON", off=(4, 0))
    arrow(ax, (57.2, 32), (66.8, 32), "merchant, ฿,\ndate, category", off=(0, 3.4))
    ax.plot([74, 74, 7.5], [39.2, 45, 45], color=INK, lw=1)
    arrow(ax, (7.5, 45), (7.5, 28), None)
    ax.text(40, 46.6, "fields shown on the verify screen; user edits and confirms", ha="center", fontsize=8.5, color=MUTED)
    arrow(ax, (74, 24.8), (74, 17.2), "confirmed fields", off=(-8, 0))
    arrow(ax, (81, 12), (86, 20), "expense", off=(-1.5, 1.5))
    arrow(ax, (90, 25), (80.6, 29.6), "possible\nduplicates", off=(5.5, 1.6))
    arrow(ax, (80.5, 7), (84, 4.5), "asset id", off=(0, -2))
    save(fig, "fig3_6_dfd_scan.png")


def dfd_coach():
    import math
    fig, ax = canvas(10, 4.8)
    box(ax, 1, 20, 13, 10, "Thai user", rounded=False, fs=9.5, bold=True)
    dfd_store(ax, 14, 40, 16, "users", "D1")
    proc(ax, 27, 25, "2.1\nBuild\nprompt")
    proc(ax, 51, 25, "2.2\nReason and\ncall tools")
    proc(ax, 75, 25, "2.3\nExecute\ntool")
    proc(ax, 51, 6.5, "2.4\nPersist\nturn", r=6)
    box(ax, 41, 38, 20, 7, "Gemini function calling", rounded=False, fs=8.8, bold=True)
    for y, lab, code in ((37, "transactions", "D2"), (27.5, "summaries", "D3"), (18, "subscriptions", "D4")):
        dfd_store(ax, 85, y, 14, lab, code)
        ang = math.atan2(y + 2.5 - 25, 85 - 75)
        arrow(ax, (75 + 7.2 * math.cos(ang), 25 + 7.2 * math.sin(ang)), (85, y + 2.5), None, style="<|-|>")
    dfd_store(ax, 68, 4, 16, "chat_messages", "D5")
    arrow(ax, (14, 26), (19.8, 26), "question", off=(0, 2.2))
    arrow(ax, (24, 40), (26, 32.3), "profile", off=(-4, 0))
    arrow(ax, (34.2, 25), (43.8, 25), "prompt, date\n+ 7 tools", off=(0, 3.4))
    arrow(ax, (49, 32.2), (49, 38), None)
    arrow(ax, (53, 38), (53, 32.2), None)
    ax.text(55, 35, "call / response", fontsize=8, color=MUTED)
    arrow(ax, (58.2, 26.5), (67.8, 26.5), "tool call", off=(0, 2))
    arrow(ax, (67.8, 23.5), (58.2, 23.5), "result", off=(0, -2))
    arrow(ax, (51, 17.8), (51, 12.5), "answer", off=(-4.5, 0))
    arrow(ax, (57, 6.5), (68, 6.5), None)
    arrow(ax, (45, 6.5), (8, 20), "answer, actions_taken", off=(-2, -2.5), rad=-0.1)
    save(fig, "fig3_7_dfd_coach.png")


# ---------------------------------------------------------------- 3.8 slip capture activity
def activity():
    fig, ax = canvas(10, 5.6)
    ax.add_patch(Circle((8, 50), 1.5, fc=INK))
    ax.add_patch(Circle((8, 30), 1.5, fc=INK))
    ax.text(8, 53, "manual", ha="center", fontsize=8.5, color=MUTED)
    ax.text(8, 33, "automatic", ha="center", fontsize=8.5, color=MUTED)
    box(ax, 17, 45, 15, 9, "Tap Scan,\ncapture photo", fs=8.6)
    box(ax, 17, 25, 15, 9, "App resumed:\nwatcher lists\nslip albums", fs=8.4)
    # decision
    from matplotlib.patches import Polygon
    ax.add_patch(Polygon([(40, 29.5), (45, 34), (50, 29.5), (45, 25)], fc="white", ec=INK))
    ax.text(45, 29.5, "new?", ha="center", va="center", fontsize=8.5)
    box(ax, 38, 11, 14, 7, "wait for next\nresume", fs=8.2, fc="white", ls="--")
    box(ax, 55, 25, 14, 9, "Offer slip in\nbottom sheet", fs=8.6)
    box(ax, 55, 45, 14, 9, "Upload image", fs=8.6)
    box(ax, 73, 45, 12, 9, "Gemini\nextracts", fs=8.6, fc=FILL3)
    box(ax, 73, 25, 12, 9, "Verify screen:\nedit, split,\nconfirm", fs=8.2, fc=FILL, ec=ACCENT)
    box(ax, 87.5, 27, 11.5, 8, "Same amount\nwithin a day?\nwarn first", fs=7.8, fc="white", ls="--")
    ax.plot([85, 87.5], [30.5, 30.5], color=INK, lw=1, ls="--")
    box(ax, 73, 6, 12, 9, "Save expense,\ninvalidate month", fs=8.2)
    box(ax, 88, 6, 11, 9, "Mark slip\nprocessed", fs=8.2, fc=FILL, ec=ACCENT)
    ax.add_patch(Circle((93.5, 22), 1.8, fc="white", ec=INK))
    ax.add_patch(Circle((93.5, 22), 1.0, fc=INK))
    arrow(ax, (9.5, 50), (17, 50))
    arrow(ax, (9.5, 30), (17, 30))
    arrow(ax, (32, 29.5), (40, 29.5))
    arrow(ax, (45, 25), (45, 18), "no", off=(2, 0))
    arrow(ax, (50, 29.5), (55, 29.5), "yes", off=(0, 1.8))
    arrow(ax, (62, 34), (62, 45))
    arrow(ax, (32, 49.5), (55, 49.5))
    arrow(ax, (69, 49.5), (73, 49.5))
    arrow(ax, (79, 45), (79, 34))
    arrow(ax, (79, 25), (79, 15))
    arrow(ax, (85, 10.5), (88, 10.5))
    arrow(ax, (93.5, 15), (93.5, 20))
    ax.text(50, 1.5, "Extraction writes nothing; the slip is marked processed only after its expense is saved.",
            ha="center", fontsize=8.5, color=MUTED, style="italic")
    save(fig, "fig3_8_activity.png")


# ---------------------------------------------------------------- 3.9 coach sequence
def sequence():
    fig, ax = canvas(10, 6.4)
    parts = ["Flutter app", "Fiber API", "Orchestrator", "Gemini 3.5", "MongoDB"]
    xs = [8, 28, 50, 72, 92]
    for x, p in zip(xs, parts):
        box(ax, x - 8, 57, 16, 5.5, p, fc=FILL2, fs=9, bold=True)
        ax.plot([x, x], [3, 57], color="#94a3b8", lw=0.9, ls=(0, (4, 3)))
    msgs = [
        (0, 1, 53, "POST /api/coach/ask"),
        (1, 2, 49.5, "ProcessQuery (45 s budget)"),
        (2, 4, 46, "load profile"),
        (2, 3, 42, "system prompt + date + 7 tool declarations"),
    ]
    for a, b, y, t in msgs:
        arrow(ax, (xs[a], y), (xs[b], y), t, off=(0, 1.3))
    ax.add_patch(Rectangle((40, 14.5), 58, 24.5, fc="none", ec=ACCENT, lw=1.1))
    ax.add_patch(Rectangle((40, 36), 17, 3, fc=ACCENT, ec=ACCENT))
    ax.text(48.5, 37.5, "loop [≤ 5 turns]", ha="center", va="center", fontsize=8, color="white", fontweight="bold")
    arrow(ax, (xs[3], 34), (xs[2], 34), "functionCall: get_transactions", off=(0, 1.3))
    arrow(ax, (xs[2], 30), (xs[4], 30), "dispatchTool → agent query", off=(0, 1.3))
    arrow(ax, (xs[4], 26.5), (xs[2], 26.5), "rows (Thai time)", off=(0, 1.3), ls="--")
    arrow(ax, (xs[2], 22.5), (xs[3], 22.5), "functionResponse", off=(0, 1.3))
    arrow(ax, (xs[3], 18), (xs[2], 18), "text, no tool call → exit", off=(0, 1.3), ls="--")
    arrow(ax, (xs[2], 11), (xs[4], 11), "persist turn to chat_messages", off=(0, 1.3))
    arrow(ax, (xs[2], 7), (xs[1], 7), "response, tools_used", off=(0, 1.3), ls="--")
    arrow(ax, (xs[1], 3.5), (xs[0], 3.5), "answer + actions_taken", off=(0, 1.3), ls="--")
    save(fig, "fig3_9_sequence.png")


# ---------------------------------------------------------------- 3.10 coach state diagram
def state_coach():
    fig, ax = canvas(10, 4.8)
    ax.add_patch(Circle((4, 30), 1.6, fc=INK))
    st = {
        "Loading history": (10, 25, 15),
        "Idle": (30, 25, 12),
        "Sending": (47, 25, 12),
        "Thinking\n(≤ 5 tool calls)": (64, 25, 15),
        "Showing reply": (84, 25, 14),
    }
    for k, (x, y, w) in st.items():
        hl = k.startswith("Thinking")
        box(ax, x, y, w, 10, k, fc=FILL if hl else FILL2, ec=ACCENT if hl else INK, fs=9)
    box(ax, 64, 4, 15, 9, "Error reply", fc=FILL2, fs=9)
    arrow(ax, (5.6, 30), (10, 30))
    arrow(ax, (25, 30), (30, 30), "loaded", off=(0, 2))
    arrow(ax, (42, 30), (47, 30), "send", off=(0, 2))
    arrow(ax, (59, 30), (64, 30))
    arrow(ax, (79, 30), (84, 30), "text", off=(0, 2))
    arrow(ax, (91, 35), (36, 35), "ready for the next question", off=(0, 7.5), rad=0.28)
    arrow(ax, (71.5, 25), (71.5, 13), "timeout or\nnetwork error", off=(7, 0))
    arrow(ax, (64, 8.5), (36, 25), "user retries", off=(-4, -3), rad=-0.15)
    save(fig, "fig3_10_state_coach.png")


# ---------------------------------------------------------------- 3.11 bill state diagram
def state_bill():
    fig, ax = canvas(10, 3.8)
    ax.add_patch(Circle((3, 20), 1.6, fc=INK))
    st = [("Upcoming\n> 7 days", 8), ("Due soon\n1-7 days", 29), ("Due today", 50), ("Overdue", 71)]
    for t, x in st:
        box(ax, x, 15, 15, 10, t, fc=FILL2, fs=9)
    box(ax, 40, 0.5, 18, 8, "Paused\n(active = false)", fc="white", fs=8.8, ls="--")
    arrow(ax, (4.6, 20), (8, 20), "create", off=(0, 2))
    arrow(ax, (23, 20), (29, 20), "time", off=(0, 2))
    arrow(ax, (44, 20), (50, 20), "time", off=(0, 2))
    arrow(ax, (65, 20), (71, 20), "time", off=(0, 2))
    for x in (36, 57, 78):
        arrow(ax, (x, 25), (15, 25), None, rad=0.35, color=ACCENT)
    ax.text(45, 36.5, "Mark paid: log expense and advance due date by one cycle (a repeat receives 409)",
            ha="center", fontsize=8.5, color=ACCENT)
    arrow(ax, (86, 17), (58, 5), "pause (from any state)", off=(6, 1.5), ls="--")
    arrow(ax, (40, 5), (15, 15), "resume", off=(-2, -1.5), ls="--")
    save(fig, "fig3_11_state_bill.png")


# ---------------------------------------------------------------- 3.12 site map
def sitemap():
    fig, ax = canvas(10, 5.0)
    box(ax, 42, 42, 16, 6, "Splash", fs=9, bold=True)
    box(ax, 22, 32, 16, 6, "Login / Sign up", fs=9)
    box(ax, 62, 32, 16, 6, "Initial setup\n(budget)", fs=8.8)
    arrow(ax, (46, 42), (32, 38))
    arrow(ax, (54, 42), (68, 38))
    arrow(ax, (38, 35), (62, 35))
    ax.add_patch(FancyBboxPatch((1, 1), 98, 27, boxstyle="round,pad=0,rounding_size=1.5", fc="#fafafa", ec="#cbd5e1"))
    ax.text(97, 25.5, "bottom navigation (5 slots)", fontsize=8.5, color=MUTED, style="italic", ha="right")
    tabs = [("Home\n(dashboard)", 4), ("History", 23), ("+ Action hub", 42), ("AI Coach", 61), ("Profile", 80)]
    for t, x in tabs:
        box(ax, x, 17, 16, 7, t, fc=FILL if "+" in t else "white", ec=ACCENT if "+" in t else INK, fs=8.8, bold=True)
    arrow(ax, (70, 32), (12, 24), rad=0.1)
    subs = [("Upcoming bills card\n→ Subscriptions", 4), ("Transaction detail\n(edit / delete)", 23),
            ("Scanner → Processing\n→ Verify · Manual add", 42), ("Chat history\nrestored from API", 61),
            ("Account settings · Security\nSlip folders · Bills", 80)]
    for t, x in subs:
        box(ax, x - 1, 3, 18, 9, t, fc="white", fs=7.8)
        arrow(ax, (x + 8, 17), (x + 8, 12))
    save(fig, "fig3_12_sitemap.png")


# ---------------------------------------------------------------- 4.1 module structure
def modules():
    fig, ax = canvas(10, 4.6)
    groups = [
        ("Identity and profile", ["Sign up / sign in", "Initial setup", "Profile · photo", "Delete account"], 1),
        ("Expense capture", ["Camera scan", "Auto-Detect", "Verify screen", "Manual add"], 21),
        ("Ledger and budget", ["History + filters", "Transaction detail", "Monthly summary", "Budget donut"], 41),
        ("AI Coach", ["Orchestrator", "Retrieval agent", "Action agent", "Research agent"], 61),
        ("Bills", ["Subscription CRUD", "Mark paid (409)", "Due-date rules", "Local reminders"], 81),
    ]
    for title, items, x in groups:
        ax.add_patch(FancyBboxPatch((x, 3), 18, 40, boxstyle="round,pad=0,rounding_size=1.2", fc="#fafafa",
                                    ec=ACCENT if title == "AI Coach" else "#94a3b8", lw=1.2))
        ax.text(x + 9, 39.5, title, ha="center", fontsize=9.2, fontweight="bold")
        for i, it in enumerate(items):
            box(ax, x + 1.5, 29 - i * 8, 15, 6, it, fc="white", fs=8.3)
    save(fig, "fig4_1_modules.png")


if __name__ == "__main__":
    for f in (fishbone, gantt, pert, existing_flow, use_case, architecture, erd, dfd_context, dfd_scan, dfd_coach,
              activity, sequence, state_coach, state_bill, sitemap, modules):
        f()
        print("drew", f.__name__)
