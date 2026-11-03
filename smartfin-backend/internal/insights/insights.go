// Package insights finds spending worth reviewing — the coach's answer to "what
// are my bad expenses?". Gemini cannot answer that from a raw transaction list:
// "bad" needs a definition, and a model asked to invent one produces a different
// verdict every time. These rules are deterministic, compare the user only with
// their own history, and give a plain reason for every item, so the coach can
// explain each one and the evaluation can check it.
//
// Nothing here is a verdict. Essentials (Bills, Groceries, Health, Transport) are
// never flagged, and "Other" is not judged because it is mostly transfers to
// people, which say nothing about what was bought.
//
// It replaces detect_spending_anomalies, removed in Sept 2026. That tool used the
// mean and standard deviation, which one large purchase drags up far enough to
// hide itself; the outlier check here uses the median and MAD instead.
package insights

import (
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
)

// Thresholds. Each one is deliberately conservative: a missed item costs less
// than telling someone a normal purchase was a mistake.
const (
	// Unusual purchases: a robust z-score of 3.5 is the Iglewicz–Hoaglin outlier
	// cut-off. The purchase must also be at least 3× the category's typical
	// amount and ฿1,000: Food mixes coffees with dinners, and at 2× an ordinary
	// ฿1,100 restaurant meal was flagged against a ฿380 typical coffee.
	MinHistory       = 4
	RobustZCut       = 3.5
	MinTimesTypical  = 3.0
	MinUnusualAmount = 1000

	// Small habits: the same merchant at least 4 times in the month, ฿500 or
	// less a visit, adding up to ฿1,000 or more.
	HabitMinCount   = 4
	HabitMaxTypical = 500
	HabitMinTotal   = 1000

	// Growing categories: compared with the average of the previous 3 months,
	// counting only months with expenses recorded (at least 2 needed), up by 30%
	// and by ฿1,000 or more.
	BaselineMonths    = 3
	MinBaselineMonths = 2
	GrowthMinPct      = 30
	GrowthMinIncrease = 1000

	// Discretionary share at or above this percentage is marked high.
	HighDiscretionaryPct = 50
)

// Essential categories are never flagged. Discretionary ones are the only ones
// judged. Anything else ("Other") is reported as unclassified.
var (
	Essential     = []string{"Bills", "Groceries", "Health", "Transport"}
	Discretionary = []string{"Food", "Shopping", "Entertainment"}
)

func isEssential(cat string) bool     { return contains(Essential, cat) }
func isDiscretionary(cat string) bool { return contains(Discretionary, cat) }

func contains(list []string, s string) bool {
	for _, x := range list {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

// UnusualPurchase is one expense far above what the user usually pays in its category.
type UnusualPurchase struct {
	Merchant      string  `json:"merchant"`
	Category      string  `json:"category"`
	Amount        int64   `json:"amount"`
	Date          string  `json:"date"`
	TypicalAmount int64   `json:"typical_amount"`
	TimesTypical  float64 `json:"times_typical"`
	Reason        string  `json:"reason"`
}

// Habit is a merchant visited often for small amounts that add up.
type Habit struct {
	Merchant         string `json:"merchant"`
	Category         string `json:"category"`
	Count            int    `json:"count"`
	Total            int64  `json:"total"`
	TypicalAmount    int64  `json:"typical_amount"`
	YearlyAtThisPace int64  `json:"yearly_at_this_pace"`
	Reason           string `json:"reason"`
}

// Growth is a discretionary category well above its recent monthly average.
type Growth struct {
	Category        string   `json:"category"`
	ThisMonth       int64    `json:"this_month"`
	MonthlyAverage  int64    `json:"monthly_average"`
	Increase        int64    `json:"increase"`
	PercentIncrease *int64   `json:"percent_increase,omitempty"` // nil when the average was ฿0
	ComparedWith    []string `json:"compared_with"`
	BiggestPurchase string   `json:"biggest_purchase,omitempty"`
	Reason          string   `json:"reason"`
}

// Share splits the month's spending into essential, discretionary and unclassified.
type Share struct {
	DiscretionaryTotal int64 `json:"discretionary_total"`
	EssentialTotal     int64 `json:"essential_total"`
	UnclassifiedTotal  int64 `json:"unclassified_total"`
	DiscretionaryPct   int64 `json:"discretionary_percent"`
	High               bool  `json:"high"`
}

// Overlap is two or more active subscriptions in the same discretionary category.
type Overlap struct {
	Category     string   `json:"category"`
	Names        []string `json:"names"`
	MonthlyTotal int64    `json:"monthly_total"`
	Reason       string   `json:"reason"`
}

// Report is the tool's answer for one month.
type Report struct {
	Month                    string            `json:"month"`
	TotalSpent               int64             `json:"total_spent"`
	TransactionCount         int               `json:"transaction_count"`
	UnusualPurchases         []UnusualPurchase `json:"unusual_purchases"`
	FrequentSmallPurchases   []Habit           `json:"frequent_small_purchases"`
	GrowingCategories        []Growth          `json:"growing_categories"`
	DiscretionaryShare       Share             `json:"discretionary_share"`
	OverlappingSubscriptions []Overlap         `json:"overlapping_subscriptions"`
	NeverFlagged             []string          `json:"never_flagged"`
}

// FindingCount is how many items the report flags for review.
func (r Report) FindingCount() int {
	n := len(r.UnusualPurchases) + len(r.FrequentSmallPurchases) + len(r.GrowingCategories) + len(r.OverlappingSubscriptions)
	if r.DiscretionaryShare.High {
		n++
	}
	return n
}

// ResolveMonth picks the month to analyse. An explicit month is used as given.
// For "current" or blank it is the current Thai month, unless that month has no
// expenses yet — then the latest month that does, with a note saying so, because
// on the 1st of a month "my bad expenses" would otherwise always be empty.
func ResolveMonth(txs []models.Transaction, requested string, now time.Time) (month, note string) {
	requested = strings.TrimSpace(requested)
	if requested != "" && requested != "current" {
		return requested, ""
	}
	current := summaries.StringOf(now)
	var latest string
	for _, t := range txs {
		if t.Type != "" && t.Type != "expense" {
			continue
		}
		m := summaries.StringOf(t.Date)
		if m == current {
			return current, ""
		}
		if m < current && m > latest {
			latest = m
		}
	}
	if latest == "" {
		return current, ""
	}
	return latest, fmt.Sprintf("No expenses are recorded in %s yet, so this covers %s, the latest month with expenses. Say so in the answer.", current, latest)
}

// Analyze runs every check for one month ("YYYY-MM", Thai time). txs may hold
// any history; only expenses dated before the month's end are used, so a past
// month is judged only against what came before it. subs should be the active
// subscriptions.
func Analyze(txs []models.Transaction, subs []models.Subscription, month string) (Report, error) {
	start, end, err := summaries.Bounds(month)
	if err != nil {
		return Report{}, err
	}
	r := Report{
		Month:                    month,
		UnusualPurchases:         []UnusualPurchase{},
		FrequentSmallPurchases:   []Habit{},
		GrowingCategories:        []Growth{},
		OverlappingSubscriptions: []Overlap{},
		NeverFlagged:             Essential,
	}

	var history []models.Transaction
	for _, t := range txs {
		if (t.Type != "" && t.Type != "expense") || !t.Date.Before(end) {
			continue
		}
		t.Category = strings.TrimSpace(t.Category)
		history = append(history, t)
	}
	// Oldest first, so every list the coach reads is in date order.
	sort.SliceStable(history, func(i, j int) bool { return history[i].Date.Before(history[j].Date) })
	// Positions in history, so a purchase can be left out of its own baseline
	// without relying on IDs.
	var inMonth []int
	for i, t := range history {
		if !t.Date.Before(start) {
			inMonth = append(inMonth, i)
		}
	}

	for _, i := range inMonth {
		t := history[i]
		r.TotalSpent += t.Amount
		switch {
		case isDiscretionary(t.Category):
			r.DiscretionaryShare.DiscretionaryTotal += t.Amount
		case isEssential(t.Category):
			r.DiscretionaryShare.EssentialTotal += t.Amount
		default:
			r.DiscretionaryShare.UnclassifiedTotal += t.Amount
		}
	}
	r.TransactionCount = len(inMonth)
	if r.TotalSpent > 0 {
		r.DiscretionaryShare.DiscretionaryPct = pct(r.DiscretionaryShare.DiscretionaryTotal, r.TotalSpent)
		r.DiscretionaryShare.High = r.DiscretionaryShare.DiscretionaryPct >= HighDiscretionaryPct
	}

	thisMonth := make([]models.Transaction, len(inMonth))
	for k, i := range inMonth {
		thisMonth[k] = history[i]
	}
	r.UnusualPurchases = unusual(inMonth, history)
	r.FrequentSmallPurchases = habits(thisMonth)
	r.GrowingCategories = growth(thisMonth, history, month)
	r.OverlappingSubscriptions = overlaps(subs)
	return r, nil
}

func unusual(inMonth []int, history []models.Transaction) []UnusualPurchase {
	out := []UnusualPurchase{}
	for _, i := range inMonth {
		t := history[i]
		if !isDiscretionary(t.Category) || t.Amount < MinUnusualAmount {
			continue
		}
		// Every other purchase in the category up to the month's end. The
		// purchase itself is left out, so it cannot raise its own baseline.
		var others []float64
		for j, h := range history {
			if j != i && strings.EqualFold(h.Category, t.Category) {
				others = append(others, float64(h.Amount))
			}
		}
		if len(others) < MinHistory {
			continue
		}
		med := median(others)
		if med <= 0 || float64(t.Amount) < MinTimesTypical*med {
			continue
		}
		dev := make([]float64, len(others))
		for i, v := range others {
			dev[i] = math.Abs(v - med)
		}
		mad := median(dev)
		// With MAD = 0 every earlier purchase was the same amount, so the 3×
		// rule above is the whole test.
		x := float64(t.Amount)
		if mad > 0 && 0.6745*(x-med)/mad < RobustZCut {
			continue
		}
		times := math.Round(x/med*10) / 10
		typical := int64(math.Round(med))
		out = append(out, UnusualPurchase{
			Merchant: t.Merchant, Category: t.Category, Amount: t.Amount,
			Date:          t.Date.In(summaries.Zone).Format("2006-01-02"),
			TypicalAmount: typical, TimesTypical: times,
			Reason: fmt.Sprintf("%s at %s is about %.1f× your typical %s purchase of %s.",
				summaries.Baht(t.Amount), t.Merchant, times, t.Category, summaries.Baht(typical)),
		})
	}
	return out
}

func habits(inMonth []models.Transaction) []Habit {
	type group struct {
		name, cat string
		amounts   []float64
		total     int64
	}
	groups := map[string]*group{}
	var order []string
	for _, t := range inMonth {
		if !isDiscretionary(t.Category) {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(t.Merchant))
		if key == "" {
			continue
		}
		g, ok := groups[key]
		if !ok {
			g = &group{name: strings.TrimSpace(t.Merchant), cat: t.Category}
			groups[key] = g
			order = append(order, key)
		}
		g.amounts = append(g.amounts, float64(t.Amount))
		g.total += t.Amount
	}
	out := []Habit{}
	for _, key := range order {
		g := groups[key]
		typical := int64(math.Round(median(g.amounts)))
		if len(g.amounts) < HabitMinCount || typical > HabitMaxTypical || g.total < HabitMinTotal {
			continue
		}
		out = append(out, Habit{
			Merchant: g.name, Category: g.cat, Count: len(g.amounts), Total: g.total,
			TypicalAmount: typical, YearlyAtThisPace: g.total * 12,
			Reason: fmt.Sprintf("%d visits to %s this month, about %s each, add up to %s — %s a year at this pace.",
				len(g.amounts), g.name, summaries.Baht(typical), summaries.Baht(g.total), summaries.Baht(g.total*12)),
		})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Total > out[j].Total })
	return out
}

func growth(inMonth, history []models.Transaction, month string) []Growth {
	// The months just before this one that have any expense recorded. A month
	// with none is a month the app was not used — before the user started, or a
	// gap such as demo data followed by real use — not a month they spent ฿0,
	// and counting it as ฿0 made every category look like it had grown.
	recorded := map[string]bool{}
	for _, t := range history {
		recorded[summaries.StringOf(t.Date)] = true
	}
	start, _, _ := summaries.Bounds(month)
	var baseline []string
	for i := 1; i <= BaselineMonths; i++ {
		if m := summaries.StringOf(start.AddDate(0, -i, 0)); recorded[m] {
			baseline = append(baseline, m)
		}
	}
	if len(baseline) < MinBaselineMonths {
		return []Growth{}
	}
	sort.Strings(baseline)

	this := map[string]int64{}
	biggest := map[string]models.Transaction{}
	for _, t := range inMonth {
		if !isDiscretionary(t.Category) {
			continue
		}
		this[t.Category] += t.Amount
		if t.Amount > biggest[t.Category].Amount {
			biggest[t.Category] = t
		}
	}
	past := map[string]int64{}
	for _, t := range history {
		if contains(baseline, summaries.StringOf(t.Date)) && isDiscretionary(t.Category) {
			past[t.Category] += t.Amount
		}
	}

	out := []Growth{}
	for _, cat := range Discretionary {
		now := this[cat]
		avg := int64(math.Round(float64(past[cat]) / float64(len(baseline))))
		inc := now - avg
		if inc < GrowthMinIncrease || (avg > 0 && inc*100 < avg*GrowthMinPct) {
			continue
		}
		g := Growth{
			Category: cat, ThisMonth: now, MonthlyAverage: avg, Increase: inc,
			ComparedWith: baseline,
		}
		if b, ok := biggest[cat]; ok {
			g.BiggestPurchase = fmt.Sprintf("%s %s", b.Merchant, summaries.Baht(b.Amount))
		}
		if avg > 0 {
			p := pct(inc, avg)
			g.PercentIncrease = &p
			g.Reason = fmt.Sprintf("%s is %s this month, up %d%% (%s more) on your %d-month average of %s.",
				cat, summaries.Baht(now), p, summaries.Baht(inc), len(baseline), summaries.Baht(avg))
		} else {
			g.Reason = fmt.Sprintf("%s is %s this month, after nothing in the previous %d months.",
				cat, summaries.Baht(now), len(baseline))
		}
		out = append(out, g)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Increase > out[j].Increase })
	return out
}

func overlaps(subs []models.Subscription) []Overlap {
	byCat := map[string][]models.Subscription{}
	for _, s := range subs {
		if s.Active && isDiscretionary(s.Category) {
			byCat[s.Category] = append(byCat[s.Category], s)
		}
	}
	out := []Overlap{}
	for _, cat := range Discretionary {
		group := byCat[cat]
		if len(group) < 2 {
			continue
		}
		o := Overlap{Category: cat}
		for _, s := range group {
			o.Names = append(o.Names, s.Name)
			o.MonthlyTotal += summaries.MonthlyEquivalent(s.Amount, s.BillingCycle)
		}
		o.Reason = fmt.Sprintf("%d active %s subscriptions (%s) cost %s a month together.",
			len(group), cat, strings.Join(o.Names, ", "), summaries.Baht(o.MonthlyTotal))
		out = append(out, o)
	}
	return out
}

// Figures lists every amount the report states, so the evaluation can accept
// them as grounded rather than as numbers the coach invented.
func (r Report) Figures() []int64 {
	f := []int64{r.TotalSpent, r.DiscretionaryShare.DiscretionaryTotal, r.DiscretionaryShare.EssentialTotal,
		r.DiscretionaryShare.UnclassifiedTotal, r.DiscretionaryShare.DiscretionaryPct}
	for _, u := range r.UnusualPurchases {
		f = append(f, u.Amount, u.TypicalAmount, u.Amount-u.TypicalAmount)
	}
	for _, h := range r.FrequentSmallPurchases {
		f = append(f, int64(h.Count), h.Total, h.TypicalAmount, h.YearlyAtThisPace)
	}
	for _, g := range r.GrowingCategories {
		f = append(f, g.ThisMonth, g.MonthlyAverage, g.Increase)
		if g.PercentIncrease != nil {
			f = append(f, *g.PercentIncrease)
		}
	}
	for _, o := range r.OverlappingSubscriptions {
		f = append(f, int64(len(o.Names)), o.MonthlyTotal)
	}
	return f
}

func median(v []float64) float64 {
	if len(v) == 0 {
		return 0
	}
	s := append([]float64(nil), v...)
	sort.Float64s(s)
	n := len(s)
	if n%2 == 1 {
		return s[n/2]
	}
	return (s[n/2-1] + s[n/2]) / 2
}

func pct(part, whole int64) int64 {
	if whole == 0 {
		return 0
	}
	return int64(math.Round(float64(part) * 100 / float64(whole)))
}
