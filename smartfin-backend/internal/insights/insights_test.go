package insights

import (
	"strings"
	"testing"
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
)

func tx(y int, m time.Month, d int, merchant string, amount int64, cat string) models.Transaction {
	return models.Transaction{Merchant: merchant, Amount: amount, Category: cat, Type: "expense",
		Date: time.Date(y, m, d, 12, 0, 0, 0, summaries.Zone)}
}

// steady is three months of ordinary spending, a baseline for every check.
func steady() []models.Transaction {
	var out []models.Transaction
	for _, m := range []time.Month{1, 2, 3} {
		out = append(out,
			tx(2026, m, 2, "Lotus's", 2800, "Groceries"),
			tx(2026, m, 5, "Cafe Amazon", 60, "Food"),
			tx(2026, m, 9, "MK Restaurant", 900, "Food"),
			tx(2026, m, 12, "Uniqlo", 1200, "Shopping"),
			tx(2026, m, 20, "Netflix", 419, "Entertainment"),
			tx(2026, m, 25, "True Move H", 599, "Bills"),
		)
	}
	return out
}

func analyze(t *testing.T, txs []models.Transaction, subs []models.Subscription, month string) Report {
	t.Helper()
	r, err := Analyze(txs, subs, month)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestSteadyMonthFlagsNothing(t *testing.T) {
	r := analyze(t, steady(), nil, "2026-03")
	if n := r.FindingCount(); n != 0 {
		t.Errorf("an ordinary month must flag nothing, got %d: %+v", n, r)
	}
	if r.TotalSpent != 2800+60+900+1200+419+599 {
		t.Errorf("total = %d", r.TotalSpent)
	}
}

func TestUnusualPurchase(t *testing.T) {
	// Four earlier Netflix payments: the minimum history for a category.
	txs := append(steady(), tx(2026, 4, 20, "Netflix", 419, "Entertainment"),
		tx(2026, 4, 28, "Thai Ticket Major", 4500, "Entertainment"))
	r := analyze(t, txs, nil, "2026-04")
	if len(r.UnusualPurchases) != 1 {
		t.Fatalf("want the ticket flagged, got %+v", r.UnusualPurchases)
	}
	u := r.UnusualPurchases[0]
	if u.Merchant != "Thai Ticket Major" || u.TypicalAmount != 419 || u.Date != "2026-04-28" {
		t.Errorf("unexpected finding %+v", u)
	}
	if !strings.Contains(u.Reason, "฿4,500") || !strings.Contains(u.Reason, "฿419") {
		t.Errorf("reason must carry both figures: %q", u.Reason)
	}
}

// The old mean/stddev tool let one big purchase inflate the spread enough to hide
// a second one. The median and MAD do not move.
func TestTwoBigPurchasesAreBothFlagged(t *testing.T) {
	txs := append(steady(),
		tx(2026, 3, 26, "Siam Paragon", 9000, "Shopping"),
		tx(2026, 3, 27, "Central World", 8000, "Shopping"))
	r := analyze(t, txs, nil, "2026-03")
	if len(r.UnusualPurchases) != 2 {
		t.Errorf("want both flagged, got %+v", r.UnusualPurchases)
	}
}

func TestPurchaseBelowThreeTimesTypicalIsNotFlagged(t *testing.T) {
	txs := append(steady(), tx(2026, 3, 27, "Central World", 3000, "Shopping")) // 2.5× ฿1,200
	if r := analyze(t, txs, nil, "2026-03"); len(r.UnusualPurchases) != 0 {
		t.Errorf("2.5× typical must not be flagged: %+v", r.UnusualPurchases)
	}
}

func TestEssentialsAreNeverFlagged(t *testing.T) {
	txs := append(steady(),
		tx(2026, 3, 26, "Bumrungrad Hospital", 25000, "Health"),
		tx(2026, 3, 27, "Thai Airways", 9000, "Transport"),
		tx(2026, 3, 28, "Lotus's", 12000, "Groceries"))
	for i := 0; i < 6; i++ {
		txs = append(txs, tx(2026, 3, 10+i, "Grab Ride", 250, "Transport"))
	}
	r := analyze(t, txs, nil, "2026-03")
	if n := len(r.UnusualPurchases) + len(r.FrequentSmallPurchases) + len(r.GrowingCategories); n != 0 {
		t.Errorf("essentials must never be flagged: %+v", r)
	}
}

func TestTooLittleHistoryIsNotJudged(t *testing.T) {
	txs := []models.Transaction{
		tx(2026, 3, 1, "Netflix", 419, "Entertainment"),
		tx(2026, 3, 2, "Thai Ticket Major", 4500, "Entertainment"),
	}
	if r := analyze(t, txs, nil, "2026-03"); len(r.UnusualPurchases) != 0 || len(r.GrowingCategories) != 0 {
		t.Errorf("a new user must not be judged: %+v", r)
	}
}

func TestHabit(t *testing.T) {
	txs := steady()
	for _, d := range []int{3, 10, 17, 24, 30} {
		txs = append(txs, tx(2026, 3, d, "Starbucks Coffee", 300, "Food"))
	}
	r := analyze(t, txs, nil, "2026-03")
	if len(r.FrequentSmallPurchases) != 1 {
		t.Fatalf("want one habit, got %+v", r.FrequentSmallPurchases)
	}
	h := r.FrequentSmallPurchases[0]
	if h.Count != 5 || h.Total != 1500 || h.YearlyAtThisPace != 18000 || h.TypicalAmount != 300 {
		t.Errorf("unexpected habit %+v", h)
	}
}

func TestHabitMerchantNameIgnoresCase(t *testing.T) {
	txs := steady()
	for i, name := range []string{"Line MAN", "LINE MAN", "line man ", "Line Man"} {
		txs = append(txs, tx(2026, 3, 3+i, name, 400, "Food"))
	}
	if r := analyze(t, txs, nil, "2026-03"); len(r.FrequentSmallPurchases) != 1 {
		t.Errorf("one merchant spelled four ways is one habit: %+v", r.FrequentSmallPurchases)
	}
}

func TestGrowth(t *testing.T) {
	txs := append(steady(), tx(2026, 4, 5, "Uniqlo", 1200, "Shopping"), tx(2026, 4, 15, "Siam Paragon", 2500, "Shopping"))
	r := analyze(t, txs, nil, "2026-04")
	if len(r.GrowingCategories) != 1 {
		t.Fatalf("want Shopping flagged, got %+v", r.GrowingCategories)
	}
	g := r.GrowingCategories[0]
	if g.Category != "Shopping" || g.ThisMonth != 3700 || g.MonthlyAverage != 1200 || g.Increase != 2500 {
		t.Errorf("unexpected growth %+v", g)
	}
	if g.PercentIncrease == nil || *g.PercentIncrease != 208 {
		t.Errorf("percent = %v", g.PercentIncrease)
	}
	if len(g.ComparedWith) != 3 || g.ComparedWith[0] != "2026-01" {
		t.Errorf("baseline months = %v", g.ComparedWith)
	}
}

// Months before the user's first expense are not months they spent nothing.
func TestGrowthIgnoresMonthsBeforeFirstExpense(t *testing.T) {
	txs := []models.Transaction{
		tx(2026, 3, 5, "Uniqlo", 1200, "Shopping"),
		tx(2026, 4, 5, "Uniqlo", 1200, "Shopping"),
		tx(2026, 4, 9, "Siam Paragon", 2500, "Shopping"),
	}
	if r := analyze(t, txs, nil, "2026-04"); len(r.GrowingCategories) != 0 {
		t.Errorf("one month of history is not enough: %+v", r.GrowingCategories)
	}
}

// A past month is judged only against what came before it.
func TestLaterSpendingIsIgnored(t *testing.T) {
	txs := append(steady(), tx(2026, 5, 1, "Siam Paragon", 50000, "Shopping"))
	if r := analyze(t, txs, nil, "2026-03"); r.FindingCount() != 0 || r.TotalSpent != 5978 {
		t.Errorf("May spending leaked into March: %+v", r)
	}
}

func TestDiscretionaryShare(t *testing.T) {
	r := analyze(t, steady(), nil, "2026-03")
	s := r.DiscretionaryShare
	if s.DiscretionaryTotal != 60+900+1200+419 || s.EssentialTotal != 2800+599 || s.DiscretionaryPct != 43 || s.High {
		t.Errorf("unexpected share %+v", s)
	}
}

func TestOtherIsNotJudged(t *testing.T) {
	txs := append(steady(), tx(2026, 3, 28, "Somchai Jaidee", 20000, "Other"))
	r := analyze(t, txs, nil, "2026-03")
	if len(r.UnusualPurchases) != 0 || r.DiscretionaryShare.UnclassifiedTotal != 20000 {
		t.Errorf("a transfer to a person must not be judged: %+v", r)
	}
}

func TestOverlappingSubscriptions(t *testing.T) {
	subs := []models.Subscription{
		{Name: "Netflix", Amount: 419, BillingCycle: "monthly", Category: "Entertainment", Active: true},
		{Name: "Disney+", Amount: 289, BillingCycle: "monthly", Category: "Entertainment", Active: true},
		{Name: "YouTube Premium", Amount: 1790, BillingCycle: "yearly", Category: "Entertainment", Active: false},
		{Name: "Condo Rent", Amount: 8500, BillingCycle: "monthly", Category: "Bills", Active: true},
		{Name: "AIS Fibre", Amount: 649, BillingCycle: "monthly", Category: "Bills", Active: true},
	}
	r := analyze(t, steady(), subs, "2026-03")
	if len(r.OverlappingSubscriptions) != 1 {
		t.Fatalf("want one overlap, got %+v", r.OverlappingSubscriptions)
	}
	o := r.OverlappingSubscriptions[0]
	if o.Category != "Entertainment" || len(o.Names) != 2 || o.MonthlyTotal != 708 {
		t.Errorf("unexpected overlap %+v", o)
	}
}

func TestResolveMonth(t *testing.T) {
	txs := steady()
	now := time.Date(2026, 10, 30, 9, 0, 0, 0, summaries.Zone)

	if m, note := ResolveMonth(txs, "2026-02", now); m != "2026-02" || note != "" {
		t.Errorf("explicit month must be kept: %s %q", m, note)
	}
	m, note := ResolveMonth(txs, "current", now)
	if m != "2026-03" || !strings.Contains(note, "2026-10") {
		t.Errorf("an empty current month falls back to the latest one: %s %q", m, note)
	}
	if m, note := ResolveMonth(append(txs, tx(2026, 10, 2, "Cafe Amazon", 60, "Food")), "", now); m != "2026-10" || note != "" {
		t.Errorf("a current month with data is used: %s %q", m, note)
	}
	if m, _ := ResolveMonth(nil, "", now); m != "2026-10" {
		t.Errorf("no data at all keeps the current month: %s", m)
	}
}

func TestInvalidMonth(t *testing.T) {
	if _, err := Analyze(steady(), nil, "April"); err == nil {
		t.Error("want an error for a malformed month")
	}
}

// Demo data that ends in April followed by real use from September: October must
// not be compared with an empty July and August as if they were ฿0 months.
func TestGrowthSkipsMonthsWithNoRecords(t *testing.T) {
	txs := append(steady(),
		tx(2026, 9, 5, "Uniqlo", 1200, "Shopping"),
		tx(2026, 10, 5, "Uniqlo", 1200, "Shopping"),
		tx(2026, 10, 9, "Siam Paragon", 2500, "Shopping"))
	if r := analyze(t, txs, nil, "2026-10"); len(r.GrowingCategories) != 0 {
		t.Errorf("one recorded month in the last three is not a baseline: %+v", r.GrowingCategories)
	}

	// A one-month gap inside the window still leaves two recorded months.
	txs = append(steady(), tx(2026, 5, 5, "Uniqlo", 1200, "Shopping"),
		tx(2026, 5, 9, "Siam Paragon", 2500, "Shopping"))
	r := analyze(t, txs, nil, "2026-05") // April has no records
	if len(r.GrowingCategories) != 1 || r.GrowingCategories[0].MonthlyAverage != 1200 ||
		len(r.GrowingCategories[0].ComparedWith) != 2 {
		t.Errorf("want Shopping against a ฿1,200 average, got %+v", r.GrowingCategories)
	}
}
