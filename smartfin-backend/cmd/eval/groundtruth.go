package main

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/insights"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

// TxRow is a transaction as the evaluation needs it.
type TxRow struct {
	ID       string    `json:"id,omitempty"`
	Date     time.Time `json:"date"`
	Merchant string    `json:"merchant"`
	Type     string    `json:"type"`
	Category string    `json:"category"`
	Amount   int64     `json:"amount"`
}

// BillRow is an active subscription with its due-date fields derived in Thai time,
// the same way the API and the coach's get_subscriptions derive them.
type BillRow struct {
	Name      string `json:"name"`
	Amount    int64  `json:"amount"`
	Cycle     string `json:"cycle"`
	Category  string `json:"category"`
	DueDate   string `json:"due_date"`
	Days      int    `json:"days_until_due"`
	Status    string `json:"status"`
	MonthlyEq int64  `json:"monthly_equivalent"`
}

// UserData is everything an eval user owns.
type UserData struct {
	Name   string
	Budget int64
	Txs    []TxRow
	Bills  []BillRow
}

// LoadUserData reads a user's profile, transactions and active bills from MongoDB.
func LoadUserData(ctx context.Context, uid string, now time.Time) (UserData, error) {
	var u models.User
	if err := config.GetCollection("users").FindOne(ctx, bson.M{"firebase_uid": uid}).Decode(&u); err != nil {
		return UserData{}, fmt.Errorf("load user %s: %w", uid, err)
	}
	d := UserData{Name: u.Name, Budget: u.BudgetLimit}

	// Expenses only, as the app and the coach see them.
	cur, err := config.GetCollection("transactions").Find(ctx, bson.M{"user_id": uid, "type": "expense"},
		options.Find().SetSort(bson.D{{Key: "date", Value: -1}}))
	if err != nil {
		return d, fmt.Errorf("load transactions: %w", err)
	}
	var txs []models.Transaction
	if err := cur.All(ctx, &txs); err != nil {
		return d, fmt.Errorf("decode transactions: %w", err)
	}
	for _, tx := range txs {
		d.Txs = append(d.Txs, TxRow{ID: tx.ID.Hex(), Date: tx.Date, Merchant: tx.Merchant, Type: tx.Type, Category: tx.Category, Amount: tx.Amount})
	}

	cur, err = config.GetCollection("subscriptions").Find(ctx, bson.M{"user_id": uid, "active": true},
		options.Find().SetSort(bson.D{{Key: "next_due_date", Value: 1}}))
	if err != nil {
		return d, fmt.Errorf("load subscriptions: %w", err)
	}
	var subs []models.Subscription
	if err := cur.All(ctx, &subs); err != nil {
		return d, fmt.Errorf("decode subscriptions: %w", err)
	}
	for _, s := range subs {
		days := summaries.DaysUntil(s.NextDueDate, now)
		d.Bills = append(d.Bills, BillRow{
			Name: s.Name, Amount: s.Amount, Cycle: s.BillingCycle, Category: s.Category,
			DueDate: summaries.DueDateString(s.NextDueDate), Days: days,
			Status:    summaries.DueStatus(days, true),
			MonthlyEq: summaries.MonthlyEquivalent(s.Amount, s.BillingCycle),
		})
	}
	return d, nil
}

// Snapshot is the part of a user's state an answer must not change unless asked.
type Snapshot struct {
	BudgetLimit int64   `json:"budget_limit"`
	TxCount     int64   `json:"tx_count"`
	SubCount    int64   `json:"sub_count"`
	CoachTxs    []TxRow `json:"coach_txs,omitempty"`
}

// TakeSnapshot reads the user's writable state from MongoDB.
func TakeSnapshot(ctx context.Context, uid string) (*Snapshot, error) {
	s := &Snapshot{}
	var u models.User
	err := config.GetCollection("users").FindOne(ctx, bson.M{"firebase_uid": uid}).Decode(&u)
	if err != nil && !errors.Is(err, mongo.ErrNoDocuments) {
		return nil, err
	}
	s.BudgetLimit = u.BudgetLimit

	txCol := config.GetCollection("transactions")
	if s.TxCount, err = txCol.CountDocuments(ctx, bson.M{"user_id": uid}); err != nil {
		return nil, err
	}
	cur, err := txCol.Find(ctx, bson.M{"user_id": uid, "source": "coach_agent"})
	if err != nil {
		return nil, err
	}
	var txs []models.Transaction
	if err := cur.All(ctx, &txs); err != nil {
		return nil, err
	}
	for _, tx := range txs {
		s.CoachTxs = append(s.CoachTxs, TxRow{ID: tx.ID.Hex(), Date: tx.Date, Merchant: tx.Merchant, Type: tx.Type, Category: tx.Category, Amount: tx.Amount})
	}
	if s.SubCount, err = config.GetCollection("subscriptions").CountDocuments(ctx, bson.M{"user_id": uid}); err != nil {
		return nil, err
	}
	return s, nil
}

// Same reports whether nothing the coach can write has changed.
func (s *Snapshot) Same(o *Snapshot) bool {
	return s.BudgetLimit == o.BudgetLimit &&
		s.TxCount == o.TxCount && s.SubCount == o.SubCount && len(s.CoachTxs) == len(o.CoachTxs)
}

// Truth is the ground truth derived from a user's expense records, following
// the coach's own formula (get_budget_summary's computed path). There is no
// income: SmartFin tracks spending only.
type Truth struct {
	Budget       int64
	Months       []string
	MonthExpense map[string]int64
	CatMonth     map[string]map[string]int64 // month → category → amount
	CatTotal     map[string]int64
	MerchMonth   map[string]map[string]int64 // lower-case merchant → month → amount
	MerchTotal   map[string]int64
	Bills        []BillRow
	BillsMonthly int64
}

// BuildTruth derives totals from the records. It is pure, so it is unit-tested.
func BuildTruth(d UserData) Truth {
	t := Truth{
		Budget:       d.Budget,
		MonthExpense: map[string]int64{},
		CatMonth:     map[string]map[string]int64{}, CatTotal: map[string]int64{},
		MerchMonth: map[string]map[string]int64{}, MerchTotal: map[string]int64{},
		Bills: d.Bills,
	}
	seen := map[string]bool{}
	for _, tx := range d.Txs {
		m := summaries.StringOf(tx.Date)
		if !seen[m] {
			seen[m] = true
			t.Months = append(t.Months, m)
		}
		if tx.Type != "expense" {
			continue
		}
		t.MonthExpense[m] += tx.Amount
		cat := tx.Category
		if strings.TrimSpace(cat) == "" {
			cat = "General"
		}
		if t.CatMonth[m] == nil {
			t.CatMonth[m] = map[string]int64{}
		}
		t.CatMonth[m][cat] += tx.Amount
		t.CatTotal[cat] += tx.Amount
		key := strings.ToLower(tx.Merchant)
		if t.MerchMonth[key] == nil {
			t.MerchMonth[key] = map[string]int64{}
		}
		t.MerchMonth[key][m] += tx.Amount
		t.MerchTotal[key] += tx.Amount
	}
	sort.Strings(t.Months)
	for _, b := range d.Bills {
		t.BillsMonthly += b.MonthlyEq
	}
	return t
}

func (t Truth) hasMonth(m string) bool {
	for _, x := range t.Months {
		if x == m {
			return true
		}
	}
	return false
}

// Resolve turns a NumSpec into the figure it names.
func (t Truth) Resolve(s NumSpec) (int64, error) {
	month := func(m string) (int64, error) {
		if !t.hasMonth(m) {
			return 0, fmt.Errorf("no records for month %s", m)
		}
		return t.MonthExpense[m], nil
	}
	switch s.Kind {
	case "month_expense":
		return month(s.Month)
	case "month_category":
		v, ok := t.CatMonth[s.Month][s.Cat]
		if !ok {
			return 0, fmt.Errorf("no %s spending in %s", s.Cat, s.Month)
		}
		return v, nil
	case "month_diff":
		a, err := month(s.Month)
		if err != nil {
			return 0, err
		}
		b, err := month(s.Month2)
		if err != nil {
			return 0, err
		}
		return abs64(a - b), nil
	case "max_month_expense":
		var max int64
		for _, m := range t.Months {
			if t.MonthExpense[m] > max {
				max = t.MonthExpense[m]
			}
		}
		if max == 0 {
			return 0, errors.New("no spending recorded")
		}
		return max, nil
	case "over_budget":
		e, err := month(s.Month)
		if err != nil {
			return 0, err
		}
		if e <= t.Budget {
			return 0, fmt.Errorf("%s is not over budget", s.Month)
		}
		return e - t.Budget, nil
	case "merchant_total":
		v, ok := t.MerchTotal[strings.ToLower(s.Name)]
		if !ok {
			return 0, fmt.Errorf("no spending at %s", s.Name)
		}
		return v, nil
	case "merchant_month":
		v, ok := t.MerchMonth[strings.ToLower(s.Name)][s.Month]
		if !ok {
			return 0, fmt.Errorf("no spending at %s in %s", s.Name, s.Month)
		}
		return v, nil
	case "bill_amount":
		for _, b := range t.Bills {
			if strings.EqualFold(b.Name, s.Name) {
				return b.Amount, nil
			}
		}
		return 0, fmt.Errorf("no bill named %s", s.Name)
	case "bills_monthly_total":
		return t.BillsMonthly, nil
	case "profile_budget":
		return t.Budget, nil
	case "literal":
		return s.V, nil
	}
	return 0, fmt.Errorf("unknown spec kind %q", s.Kind)
}

// AllowedBase is every figure an honest answer about this user could quote:
// amounts, totals, differences and sums of the records, the budget and the bills.
// A number outside it (after the rounding allowance in score.go) is reported as an
// unsupported figure. It is deliberately generous, so the metric is an upper bound
// on invented numbers rather than a strict count.
func (t Truth) AllowedBase(txs []TxRow) []int64 {
	set := map[int64]bool{0: true}
	add := func(v int64) { set[abs64(v)] = true }
	add(t.Budget)
	for _, tx := range txs {
		add(tx.Amount)
	}

	var totalExp int64
	for _, m := range t.Months {
		e := t.MonthExpense[m]
		totalExp += e
		add(e)
		add(t.Budget - e)
		for _, v := range t.CatMonth[m] {
			add(v)
		}
	}
	for _, mm := range t.MerchMonth {
		for _, v := range mm {
			add(v)
		}
	}
	for _, v := range t.CatTotal {
		add(v)
	}
	for _, v := range t.MerchTotal {
		add(v)
	}
	add(totalExp)
	if n := len(t.Months); n > 0 {
		add(int64(math.Round(float64(totalExp) / float64(n))))
	}
	for i, a := range t.Months {
		var run int64
		for j := i; j < len(t.Months); j++ {
			run += t.MonthExpense[t.Months[j]]
			add(run)
		}
		for _, b := range t.Months[i+1:] {
			add(t.MonthExpense[a] - t.MonthExpense[b])
			add(t.MonthExpense[a] + t.MonthExpense[b])
			for cat, v := range t.CatMonth[a] {
				if w, ok := t.CatMonth[b][cat]; ok {
					add(v - w)
				}
			}
		}
	}
	for mask := 1; mask < 1<<len(t.Bills); mask++ {
		var sum int64
		for j, b := range t.Bills {
			if mask&(1<<j) != 0 {
				sum += b.Amount
			}
		}
		add(sum)
	}
	for _, b := range t.Bills {
		add(b.Amount)
		add(b.MonthlyEq)
	}
	add(t.BillsMonthly)
	return sortedKeys(set)
}

// CaseAllowed extends the base set with the numbers the question and history
// themselves contain, and their distance to the budget and each month's
// spending ("if I raised my limit to ฿25,000" makes ฿10,000 more a fair answer).
func CaseAllowed(c Case, t Truth, base []int64) []int64 {
	set := map[int64]bool{}
	for _, v := range base {
		set[v] = true
	}
	texts := append([]string{c.Question}, c.PriorTurns...)
	for _, h := range c.History {
		texts = append(texts, h.Content)
	}
	for _, text := range texts {
		for _, n := range ExtractNumbers(text) {
			q := n.Value
			set[q] = true
			set[abs64(q-t.Budget)] = true
			for _, m := range t.Months {
				set[abs64(q-t.MonthExpense[m])] = true
			}
		}
	}
	return sortedKeys(set)
}

func sortedKeys(set map[int64]bool) []int64 {
	out := make([]int64, 0, len(set))
	for v := range set {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

// WithInsightFigures adds every figure get_spending_insights states for any
// month (typical amounts, yearly paces, averages, increases) to the allowed set.
// Those come from the user's records by a fixed rule, so quoting one is
// grounded, not invented.
func WithInsightFigures(base []int64, d UserData, t Truth) []int64 {
	var txs []models.Transaction
	for _, tx := range d.Txs {
		txs = append(txs, models.Transaction{Merchant: tx.Merchant, Amount: tx.Amount, Type: tx.Type, Category: tx.Category, Date: tx.Date})
	}
	var subs []models.Subscription
	for _, b := range d.Bills {
		subs = append(subs, models.Subscription{Name: b.Name, Amount: b.Amount, BillingCycle: b.Cycle, Category: b.Category, Active: true})
	}
	set := map[int64]bool{}
	for _, v := range base {
		set[v] = true
	}
	for _, m := range t.Months {
		r, err := insights.Analyze(txs, subs, m)
		if err != nil {
			continue
		}
		for _, v := range r.Figures() {
			set[abs64(v)] = true
		}
	}
	return sortedKeys(set)
}
