package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Meta describes a run.
type Meta struct {
	RunID         string    `json:"run_id"`
	GitSHA        string    `json:"git_sha"`
	Model         string    `json:"model"`
	Temperature   float64   `json:"temperature"`
	Repeats       int       `json:"repeats"`
	Concurrency   int       `json:"concurrency"`
	Systems       []string  `json:"systems"`
	Cases         []string  `json:"cases"`
	API           string    `json:"api"`
	ThaiDateStart string    `json:"thai_date_start"`
	ThaiDateEnd   string    `json:"thai_date_end"`
	Started       time.Time `json:"started"`
	Finished      time.Time `json:"finished"`
	Warnings      []string  `json:"warnings,omitempty"`
}

// Results is everything a run produced; -rescore reads it back.
type Results struct {
	Meta     Meta               `json:"meta"`
	Resolved map[string][]int64 `json:"resolved"` // case → required figures
	Allowed  map[string][]int64 `json:"allowed"`  // case → figures an answer may quote
	Trials   []*Trial           `json:"trials"`
}

var systemLabel = map[string]string{"agentic": "Agentic coach", "oneshot": "One-shot RAG", "noretrieval": "No retrieval"}
var systemKey = map[string]string{"agentic": "AG", "oneshot": "OS", "noretrieval": "NR"}
var categoryOrder = []string{"lookup", "aggregation", "bills", "thai", "multiturn", "nodata", "offtopic", "safety", "actions", "memory"}

func writeOutputs(res *Results, dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(res, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "results.json"), data, 0o644); err != nil {
		return err
	}
	if err := writeCSV(res, filepath.Join(dir, "answers.csv")); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "summary.md"), []byte(summaryMarkdown(res)), 0o644)
}

func writeCSV(res *Results, path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	w := csv.NewWriter(f)
	_ = w.Write([]string{"case", "category", "system", "repeat", "pass", "status", "latency_ms", "tools", "fail_reasons", "answer"})
	for _, t := range res.Trials {
		_ = w.Write([]string{t.CaseID, t.Category, t.System, fmt.Sprint(t.Repeat), fmt.Sprint(t.Score.Pass), t.Status,
			fmt.Sprint(t.LatencyMs), strings.Join(t.Tools, " "), strings.Join(t.Score.FailReasons, "; "), t.Answer})
	}
	w.Flush()
	return w.Error()
}

type agg struct {
	pass, n                                         int
	reqHit, reqTotal                                int
	unsupAnswers, answers                           int
	errors, timeouts, retries, fallbacks, falseClms int
	lat                                             []int64
}

func aggregate(trials []*Trial, system string, keep func(*Trial) bool) agg {
	var a agg
	for _, t := range trials {
		if t.System != system || !keep(t) {
			continue
		}
		a.n++
		if t.Score.Pass {
			a.pass++
		}
		a.reqHit += t.Score.RequiredHit
		a.reqTotal += t.Score.RequiredTotal
		a.retries += t.Retries
		switch t.Status {
		case "ok":
			a.answers++
			a.lat = append(a.lat, t.LatencyMs)
			if len(t.Score.Unsupported) > 0 {
				a.unsupAnswers++
			}
		case "timeout":
			a.timeouts++
		default:
			a.errors++
		}
		if t.Score.Fallback {
			a.fallbacks++
		}
		if t.Score.FalseActionClaim {
			a.falseClms++
		}
	}
	return a
}

func pct(k, n int) string {
	if n == 0 {
		return "–"
	}
	return fmt.Sprintf("%.0f%%", 100*float64(k)/float64(n))
}

func frac(k, n int) string {
	if n == 0 {
		return "–"
	}
	return fmt.Sprintf("%d/%d", k, n)
}

func percentile(values []int64, p float64) string {
	if len(values) == 0 {
		return "–"
	}
	v := append([]int64(nil), values...)
	sort.Slice(v, func(i, j int) bool { return v[i] < v[j] })
	idx := int(math.Ceil(p/100*float64(len(v)))) - 1
	if idx < 0 {
		idx = 0
	}
	return fmt.Sprintf("%.1fs", float64(v[idx])/1000)
}

func summaryMarkdown(res *Results) string {
	var b strings.Builder
	m := res.Meta
	fmt.Fprintf(&b, "# Coach evaluation — run %s\n\n", m.RunID)
	fmt.Fprintf(&b, "Model `%s` · temperature %.1f · %d repeat(s) · %d cases · Thai date %s · commit `%s` · API %s\n\n",
		m.Model, m.Temperature, m.Repeats, len(m.Cases), m.ThaiDateStart, m.GitSHA, m.API)
	for _, w := range m.Warnings {
		fmt.Fprintf(&b, "> ⚠️ %s\n\n", w)
	}
	shared := func(t *Trial) bool { return t.Scope == "shared" }

	// T1
	b.WriteString("## T1 · Headline — shared questions (same for every system)\n\n")
	b.WriteString("| System | Pass | Numeric accuracy | Answers with unsupported ฿ figures | p50 | p95 | Errors | Timeouts | Retries | Fallback replies |\n|---|---|---|---|---|---|---|---|---|---|\n")
	for _, sys := range m.Systems {
		a := aggregate(res.Trials, sys, shared)
		fmt.Fprintf(&b, "| %s | %s (%s) | %s | %s | %s | %s | %d | %d | %d | %d |\n",
			systemLabel[sys], pct(a.pass, a.n), frac(a.pass, a.n), pct(a.reqHit, a.reqTotal),
			pct(a.unsupAnswers, a.answers), percentile(a.lat, 50), percentile(a.lat, 95),
			a.errors, a.timeouts, a.retries, a.fallbacks)
	}

	// T1b
	b.WriteString("\n## T1b · Overall task success — all cases (safety, actions and memory included)\n\n")
	b.WriteString("A system that cannot perform a task — the baselines have no tools and no memory — fails it.\n\n| System | Passed | Rate |\n|---|---|---|\n")
	for _, sys := range m.Systems {
		o := aggregate(res.Trials, sys, func(*Trial) bool { return true })
		fmt.Fprintf(&b, "| %s | %s | %s |\n", systemLabel[sys], frac(o.pass, o.n), pct(o.pass, o.n))
	}

	// T2
	b.WriteString("\n## T2 · Pass by category\n\n| Category |")
	for _, sys := range m.Systems {
		b.WriteString(" " + systemLabel[sys] + " |")
	}
	b.WriteString("\n|---|" + strings.Repeat("---|", len(m.Systems)) + "\n")
	for _, cat := range categoryOrder {
		row := ""
		any := false
		for _, sys := range m.Systems {
			a := aggregate(res.Trials, sys, func(t *Trial) bool { return t.Category == cat })
			if a.n > 0 {
				any = true
			}
			row += " " + frac(a.pass, a.n) + " |"
		}
		if any {
			fmt.Fprintf(&b, "| %s |%s\n", cat, row)
		}
	}

	// T3
	var recallSum, precSum float64
	var recallN, precN, monthsCov, monthsExp, unintended, nonAction, retrieval, generation, nudges, nudgesPassed int
	for _, t := range res.Trials {
		if t.System != "agentic" {
			continue
		}
		if t.Nudged {
			nudges++
			if t.Score.Pass {
				nudgesPassed++
			}
		}
		if t.Score.ToolRecall >= 0 {
			recallSum += t.Score.ToolRecall
			recallN++
		}
		if t.Score.ToolPrecision >= 0 {
			precSum += t.Score.ToolPrecision
			precN++
		}
		monthsCov += t.Score.MonthsCovered
		monthsExp += t.Score.MonthsExpected
		if t.Category != "actions" {
			nonAction++
			if t.Score.UnintendedWrite {
				unintended++
			}
		}
		switch {
		case strings.HasPrefix(t.Score.Attribution, "retrieval"):
			retrieval++
		case strings.HasPrefix(t.Score.Attribution, "generation"):
			generation++
		}
	}
	actions := aggregate(res.Trials, "agentic", func(t *Trial) bool { return t.Category == "actions" })
	safety := aggregate(res.Trials, "agentic", func(t *Trial) bool { return t.Category == "safety" })
	memory := aggregate(res.Trials, "agentic", func(t *Trial) bool { return t.Category == "memory" })
	b.WriteString("\n## T3 · Agentic coach only\n\n| Metric | Value |\n|---|---|\n")
	fmt.Fprintf(&b, "| Actions done correctly (DB readback) | %s |\n", frac(actions.pass, actions.n))
	fmt.Fprintf(&b, "| Safety cases passed | %s |\n", frac(safety.pass, safety.n))
	fmt.Fprintf(&b, "| Cross-session memory (M3) | %s |\n", frac(memory.pass, memory.n))
	fmt.Fprintf(&b, "| Unintended writes (non-action trials) | %s |\n", frac(unintended, nonAction))
	fmt.Fprintf(&b, "| Tool recall (mean) | %s |\n", ratio(recallSum, recallN))
	fmt.Fprintf(&b, "| Tool precision (mean) | %s |\n", ratio(precSum, precN))
	fmt.Fprintf(&b, "| Expected months retrieved | %s |\n", frac(monthsCov, monthsExp))
	fmt.Fprintf(&b, "| Missing-figure failures: retrieval / generation | %d / %d |\n", retrieval, generation)
	fmt.Fprintf(&b, "| Stall nudges sent (trials that then passed) | %d (%d) |\n", nudges, nudgesPassed)
	for _, sys := range m.Systems {
		if sys == "agentic" {
			continue
		}
		a := aggregate(res.Trials, sys, func(t *Trial) bool { return t.Category == "actions" })
		fmt.Fprintf(&b, "| %s: false \"done\" claims on action requests | %s |\n", systemLabel[sys], frac(a.falseClms, a.n))
	}

	// T4
	b.WriteString("\n## T4 · Case × system (passes / repeats)\n\n| Case | Category |")
	for _, sys := range m.Systems {
		b.WriteString(" " + systemLabel[sys] + " |")
	}
	b.WriteString("\n|---|---|" + strings.Repeat("---|", len(m.Systems)) + "\n")
	for _, id := range m.Cases {
		cat := ""
		row := ""
		for _, sys := range m.Systems {
			a := aggregate(res.Trials, sys, func(t *Trial) bool {
				if t.CaseID == id {
					cat = t.Category
					return true
				}
				return false
			})
			row += " " + frac(a.pass, a.n) + " |"
		}
		fmt.Fprintf(&b, "| %s | %s |%s\n", id, cat, row)
	}

	// T5 / T6
	writeFailures := func(title string, keep func(*Trial) bool) {
		fmt.Fprintf(&b, "\n## %s\n\n| Case | System | Run | Why | Attribution | Answer (start) |\n|---|---|---|---|---|---|\n", title)
		for _, t := range res.Trials {
			if t.Score.Pass || !keep(t) {
				continue
			}
			fmt.Fprintf(&b, "| %s | %s | %d | %s | %s | %s |\n", t.CaseID, systemKey[t.System], t.Repeat,
				mdEscape(strings.Join(t.Score.FailReasons, "; ")), t.Score.Attribution, mdEscape(truncate(oneLine(t.Answer), 160)))
		}
	}
	writeFailures("T5 · Agentic failures", func(t *Trial) bool { return t.System == "agentic" })
	writeFailures("T6 · Baseline failures on shared questions", func(t *Trial) bool { return t.System != "agentic" && t.Scope == "shared" })

	// Slide values
	b.WriteString("\n## SLIDE_VALUES\n\n```\n")
	for _, sys := range m.Systems {
		k := systemKey[sys]
		a := aggregate(res.Trials, sys, shared)
		o := aggregate(res.Trials, sys, func(*Trial) bool { return true })
		fmt.Fprintf(&b, "%s_OVERALL=%s\n%s_OVERALL_FRAC=%s\n", k, pct(o.pass, o.n), k, frac(o.pass, o.n))
		fmt.Fprintf(&b, "%s_PASS=%s\n%s_PASS_FRAC=%s\n%s_NUMACC=%s\n%s_UNSUPPORTED=%s\n%s_P50=%s\n%s_P95=%s\n",
			k, pct(a.pass, a.n), k, frac(a.pass, a.n), k, pct(a.reqHit, a.reqTotal), k, pct(a.unsupAnswers, a.answers),
			k, percentile(a.lat, 50), k, percentile(a.lat, 95))
		for _, cat := range categoryOrder {
			c := aggregate(res.Trials, sys, func(t *Trial) bool { return t.Category == cat })
			if c.n > 0 {
				fmt.Fprintf(&b, "CAT_%s_%s=%s\n", strings.ToUpper(cat), k, frac(c.pass, c.n))
			}
		}
		if sys != "agentic" {
			c := aggregate(res.Trials, sys, func(t *Trial) bool { return t.Category == "actions" })
			fmt.Fprintf(&b, "%s_FALSE_CLAIMS=%s\n", k, frac(c.falseClms, c.n))
		}
	}
	fmt.Fprintf(&b, "AG_ACTIONS=%s\nAG_SAFETY=%s\nAG_MEMORY=%s\nAG_UNINTENDED_WRITES=%s\nAG_TOOL_RECALL=%s\nAG_TOOL_PRECISION=%s\nAG_MONTHS=%s\nAG_ATTR_RETRIEVAL=%d\nAG_ATTR_GENERATION=%d\n",
		frac(actions.pass, actions.n), frac(safety.pass, safety.n), frac(memory.pass, memory.n), frac(unintended, nonAction),
		ratio(recallSum, recallN), ratio(precSum, precN), frac(monthsCov, monthsExp), retrieval, generation)
	b.WriteString("```\n")
	return b.String()
}

func ratio(sum float64, n int) string {
	if n == 0 {
		return "–"
	}
	return fmt.Sprintf("%.2f", sum/float64(n))
}

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }

func mdEscape(s string) string { return strings.ReplaceAll(s, "|", "\\|") }
