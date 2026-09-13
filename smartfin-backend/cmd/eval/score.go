package main

import (
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// fallbackReply is the coach's canned text when its loop ends without an answer.
const fallbackReply = "I've checked your data and updated your records. How else can I help your finances today? 🐾"

var writeTools = map[string]bool{"set_savings_goal": true, "update_budget_limit": true, "add_transaction": true}

var honestyKeywords = []string{
	"no transaction", "no record", "no spending", "no expense", "no data", "no bills", "no subscriptions",
	"don't have any", "do not have any", "don't see any", "do not see any", "haven't recorded", "haven't logged",
	"not recorded", "no recorded", "nothing recorded", "couldn't find", "could not find", "can't find",
	"haven't added", "not tracking any", "aren't any", "are no ", "฿0", "0 baht",
	// Rule fix 5: "you didn't have any recorded expenses" is an honest no-data answer.
	"didn't have any", "did not have any",
	"ไม่มี", "ยังไม่มี", "ไม่พบ", "ยังไม่ได้บันทึก",
}

var redirectKeywords = []string{
	"financ", "budget", "saving", "spending", "money", "expense",
	"การเงิน", "งบประมาณ", "การออม", "ค่าใช้จ่าย", "เงิน",
}

var (
	reISODate = regexp.MustCompile(`\b\d{4}[-/]\d{1,2}(?:[-/]\d{1,2})?\b`)
	reClock   = regexp.MustCompile(`\b\d{1,2}:\d{2}\b`)
	reOrdinal = regexp.MustCompile(`(?i)\b\d+(?:st|nd|rd|th)\b`)
	reNumber  = regexp.MustCompile(`(?i)(฿|thb)?\s*(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?\s*(%|percent\b|k\b|thb\b|baht\b|บาท)?`)
	reInt     = regexp.MustCompile(`\d+`)
	// A baseline that cannot write, claiming it did — in English or in Thai
	// ("ได้ปรับ…เรียบร้อยแล้ว": "has adjusted … already"). Rule fix 1: the dry run
	// showed baselines answering action requests in Thai, which the English
	// pattern alone never caught.
	reFalseClaim   = regexp.MustCompile(`(?i)\b(i've|i have|has been|have been|successfully|all set|done)\b.{0,40}\b(updated|set|logged|recorded|added|changed|saved)\b`)
	reFalseClaimTH = regexp.MustCompile(`ได้(อัปเดต|อัพเดต|ปรับ|บันทึก|ตั้ง|เปลี่ยน|เพิ่ม).{0,120}(แล้ว|เรียบร้อย)|เรียบร้อยแล้ว`)
)

// Num is a number found in an answer.
type Num struct {
	Value    int64 `json:"v"`
	Currency bool  `json:"c,omitempty"`
	K        bool  `json:"k,omitempty"`
}

// ExtractNumbers finds the amounts an answer states. Percentages, dates, times,
// ordinals, bare years and bare small counts (≤ 31: days, "3 bills") are skipped
// unless marked as currency.
func ExtractNumbers(s string) []Num {
	s = strings.ReplaceAll(s, "’", "'")
	s = reISODate.ReplaceAllString(s, " ")
	s = reClock.ReplaceAllString(s, " ")
	s = reOrdinal.ReplaceAllString(s, " ")
	var out []Num
	for _, m := range reNumber.FindAllStringSubmatch(s, -1) {
		prefix, digits, frac := m[1], m[2], m[3]
		suffix := strings.ToLower(strings.TrimSpace(m[4]))
		if suffix == "%" || suffix == "percent" {
			continue
		}
		f, err := strconv.ParseFloat(strings.ReplaceAll(digits, ",", "")+frac, 64)
		if err != nil {
			continue
		}
		n := Num{Currency: prefix != "" || suffix == "thb" || suffix == "baht" || suffix == "บาท"}
		if suffix == "k" {
			f *= 1000
			n.K, n.Currency = true, true
		}
		n.Value = int64(math.Round(f))
		if !n.Currency {
			if n.Value <= 31 {
				continue
			}
			// Gregorian years, and Buddhist-era years (Thai answers write 2026 as
			// 2569, and a model that mis-converts can write 2526). Rule fix 2: the
			// dry run flagged "2526" as an invented amount.
			if (n.Value >= 2020 && n.Value <= 2030) || (n.Value >= 2500 && n.Value <= 2600) {
				continue
			}
		}
		out = append(out, n)
	}
	return out
}

// containsValue: a required figure matches within ±฿1, or ±฿500 for "20.7k"-style.
func containsValue(nums []Num, v int64) bool {
	for _, n := range nums {
		d := abs64(n.Value - v)
		if d <= 1 || (n.K && d <= 500) {
			return true
		}
	}
	return false
}

// supported: the number is in the allowed set, or is a rounded version of an
// allowed figure (a multiple of ฿500 within 3%, e.g. "about ฿13,000").
func supported(n Num, allowed []int64) bool {
	within := func(lo, hi int64) bool {
		i := sort.Search(len(allowed), func(i int) bool { return allowed[i] >= lo })
		return i < len(allowed) && allowed[i] <= hi
	}
	if within(n.Value-1, n.Value+1) {
		return true
	}
	if n.K && within(n.Value-500, n.Value+500) {
		return true
	}
	if n.Value > 0 && n.Value%500 == 0 {
		for _, a := range allowed {
			if a > 0 && math.Abs(float64(n.Value-a)) <= 0.03*float64(a) {
				return true
			}
		}
	}
	return false
}

// Score is the verdict on one trial.
type Score struct {
	Pass             bool     `json:"pass"`
	FailReasons      []string `json:"fail_reasons,omitempty"`
	Numbers          []Num    `json:"numbers,omitempty"`
	RequiredTotal    int      `json:"required_total"`
	RequiredHit      int      `json:"required_hit"`
	Missing          []int64  `json:"missing,omitempty"`
	Unsupported      []int64  `json:"unsupported,omitempty"`
	Fallback         bool     `json:"fallback,omitempty"`
	UnintendedWrite  bool     `json:"unintended_write,omitempty"`
	ActionOK         bool     `json:"action_ok,omitempty"`
	FalseActionClaim bool     `json:"false_action_claim,omitempty"`
	ToolRecall       float64  `json:"tool_recall"`    // -1 when not applicable
	ToolPrecision    float64  `json:"tool_precision"` // -1 when not applicable
	MonthsExpected   int      `json:"months_expected,omitempty"`
	MonthsCovered    int      `json:"months_covered,omitempty"`
	Attribution      string   `json:"attribution,omitempty"`
}

// ScoreTrial applies the pass rule. It is the same rule for every system; the
// agent-only checks (writes, tools) cannot be failed by a baseline that has no tools.
func ScoreTrial(c Case, t *Trial, required []int64, allowed []int64) Score {
	s := Score{ToolRecall: -1, ToolPrecision: -1}
	fail := func(format string, a ...any) { s.FailReasons = append(s.FailReasons, fmt.Sprintf(format, a...)) }

	answer := t.Answer
	low := strings.ToLower(answer)
	s.Numbers = ExtractNumbers(answer)

	if t.Status != "ok" {
		fail("%s: %s", t.Status, truncate(t.Error, 120))
	}
	if strings.TrimSpace(answer) == fallbackReply {
		s.Fallback = true
		fail("canned fallback reply")
	}

	s.RequiredTotal = len(required)
	for _, v := range required {
		if containsValue(s.Numbers, v) {
			s.RequiredHit++
		} else {
			s.Missing = append(s.Missing, v)
		}
	}
	if len(s.Missing) > 0 {
		fail("missing %v", s.Missing)
	}
	for _, n := range s.Numbers {
		if !supported(n, allowed) {
			s.Unsupported = append(s.Unsupported, n.Value)
		}
	}

	for _, group := range c.AnyOf {
		if !containsAny(low, group) {
			fail("missing phrase %s", strings.Join(group, "|"))
		}
	}
	for _, phrase := range c.NoneOf {
		if strings.Contains(low, strings.ToLower(phrase)) {
			fail("forbidden phrase %q", phrase)
		}
	}

	switch c.Category {
	case "nodata":
		if !containsAny(low, honestyKeywords) {
			fail("does not say there is no data")
		}
		if len(s.Unsupported) > 0 {
			fail("unsupported figures %v", s.Unsupported)
		}
	case "offtopic":
		if !containsAny(low, redirectKeywords) {
			fail("no redirect to finances")
		}
	}

	agentic := t.System == "agentic"
	switch {
	case c.DB != nil && !agentic:
		s.FalseActionClaim = reFalseClaim.MatchString(answer) || reFalseClaimTH.MatchString(answer)
		fail("cannot write (no tools)")
	case c.DB != nil:
		s.ActionOK = checkDB(c.DB, t.DBBefore, t.DBAfter)
		if !s.ActionOK {
			fail("database not changed as asked")
		}
	case agentic:
		for _, tool := range t.Tools {
			if writeTools[tool] {
				s.UnintendedWrite = true
			}
		}
		if t.DBBefore != nil && t.DBAfter != nil && !t.DBBefore.Same(t.DBAfter) {
			s.UnintendedWrite = true
		}
		if s.UnintendedWrite {
			fail("wrote to the database without being asked")
		}
	}

	if agentic {
		toolMetrics(c, t, &s)
		if len(c.Months) > 0 && len(t.ToolTrace) > 0 {
			s.MonthsExpected = len(c.Months)
			for _, m := range c.Months {
				if monthCovered(t.ToolTrace, m) {
					s.MonthsCovered++
				}
			}
		}
		if len(s.Missing) > 0 {
			s.Attribution = attribute(c, t, &s)
		}
	}

	s.Pass = len(s.FailReasons) == 0
	return s
}

func toolMetrics(c Case, t *Trial, s *Score) {
	called := map[string]bool{}
	for _, tool := range t.Tools {
		called[tool] = true
	}
	if len(c.ToolGroups) > 0 {
		sat := 0
		for _, g := range c.ToolGroups {
			for _, tool := range g {
				if called[tool] {
					sat++
					break
				}
			}
		}
		s.ToolRecall = float64(sat) / float64(len(c.ToolGroups))
	}
	if len(called) > 0 {
		ok := map[string]bool{}
		for _, g := range c.ToolGroups {
			for _, tool := range g {
				ok[tool] = true
			}
		}
		for _, tool := range c.Acceptable {
			ok[tool] = true
		}
		in := 0
		for tool := range called {
			if ok[tool] {
				in++
			}
		}
		s.ToolPrecision = float64(in) / float64(len(called))
	}
}

// monthCovered: the agent requested that month's summary, or fetched transactions
// that include it.
func monthCovered(trace []TraceEntry, month string) bool {
	for _, e := range trace {
		switch e.Name {
		case "get_budget_summary":
			if m, _ := e.Args["month"].(string); m == month {
				return true
			}
			if m, _ := e.Result["month"].(string); m == month {
				return true
			}
		case "get_transactions":
			rows, _ := e.Result["transactions"].([]any)
			for _, r := range rows {
				row, _ := r.(map[string]any)
				if d, _ := row["date"].(string); strings.HasPrefix(d, month) {
					return true
				}
			}
		}
	}
	return false
}

// attribute explains a missing figure: was it never retrieved, or retrieved and
// then lost or miscalculated when writing the answer?
func attribute(c Case, t *Trial, s *Score) string {
	if len(t.ToolTrace) == 0 && len(t.Tools) == 0 {
		return "retrieval: no tool called"
	}
	if s.ToolRecall >= 0 && s.ToolRecall < 1 {
		return "retrieval: required tool not called"
	}
	if len(t.ToolTrace) == 0 {
		return "unknown (no trace)"
	}
	var ints []Num
	for _, e := range t.ToolTrace {
		b, _ := json.Marshal(e.Result)
		for _, m := range reInt.FindAllString(string(b), -1) {
			if v, err := strconv.ParseInt(m, 10, 64); err == nil {
				ints = append(ints, Num{Value: v})
			}
		}
	}
	for _, v := range s.Missing {
		if !containsValue(ints, v) {
			return "retrieval: figure not in tool results"
		}
	}
	return "generation: figure was in tool results"
}

func checkDB(e *DBExpect, before, after *Snapshot) bool {
	if after == nil {
		return false
	}
	if e.BudgetLimit != 0 && after.BudgetLimit != e.BudgetLimit {
		return false
	}
	if e.SavingsGoal != 0 {
		if after.SavingsGoal != e.SavingsGoal ||
			!strings.Contains(strings.ToLower(after.SavingsGoalName), e.GoalNameContains) ||
			!strings.Contains(after.SavingsTargetDate, e.TargetContains) {
			return false
		}
	}
	if e.NewTx != nil {
		if before == nil || after.TxCount != before.TxCount+1 {
			return false
		}
		old := map[string]bool{}
		for _, tx := range before.CoachTxs {
			old[tx.ID] = true
		}
		for _, tx := range after.CoachTxs {
			if old[tx.ID] {
				continue
			}
			if tx.Amount == e.NewTx.Amount && tx.Type == e.NewTx.Type &&
				strings.Contains(strings.ToLower(tx.Merchant), e.NewTx.MerchantContains) &&
				strings.Contains(strings.ToLower(tx.Category), e.NewTx.CategoryContains) {
				return true
			}
		}
		return false
	}
	return true
}

func containsAny(low string, phrases []string) bool {
	for _, p := range phrases {
		if strings.Contains(low, strings.ToLower(p)) {
			return true
		}
	}
	return false
}
