// Command slipeval measures how accurately the slip scanner (POST
// /api/scanner/process, Gemini Vision) reads real e-slips and paper receipts.
//
// Images and labels live in smartfin-backend/eval-slips/, which is git-ignored:
// slips show names, account numbers and reference IDs. Each image is sent the way
// the app sends it (the original file, multipart), and the extracted merchant,
// amount and date are compared with labels.csv. The scanner persists nothing, so
// there is nothing to clean up.
//
//	go run ./cmd/slipeval -repeats 2                        # scan and score
//	go run ./cmd/slipeval -rescore eval-slips/results/<run> # re-score after fixing labels
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Trial is one scan of one image. It stores what the scanner returned, not the
// verdict, so labels can be corrected and re-scored without scanning again.
type Trial struct {
	File       string  `json:"file"`
	Repeat     int     `json:"repeat"`
	LatencyMs  int64   `json:"latency_ms"`
	Status     string  `json:"status"`
	Error      string  `json:"error,omitempty"`
	Merchant   string  `json:"merchant"`
	Amount     int64   `json:"amount"`
	Date       string  `json:"date"`
	Confidence float64 `json:"confidence"`
	Raw        string  `json:"raw_text,omitempty"`
	Score      Score   `json:"score"`
}

type Results struct {
	RunID   string    `json:"run_id"`
	API     string    `json:"api"`
	Repeats int       `json:"repeats"`
	RunDay  string    `json:"run_day"`
	Started time.Time `json:"started"`
	Trials  []*Trial  `json:"trials"`
}

func main() {
	api := flag.String("api", envOr("EVAL_API", "http://localhost:3001"), "SmartFin API base URL")
	dir := flag.String("dir", "eval-slips", "folder with images/ and labels.csv")
	repeats := flag.Int("repeats", 2, "scans per image")
	concurrency := flag.Int("concurrency", 3, "scans in parallel")
	timeout := flag.Duration("timeout", 90*time.Second, "per-scan timeout")
	rescoreDir := flag.String("rescore", "", "re-score an existing run with the current labels.csv")
	flag.Parse()
	log.SetFlags(0)

	labels, err := loadLabels(filepath.Join(*dir, "labels.csv"))
	if err != nil {
		log.Fatal(err)
	}

	if *rescoreDir != "" {
		data, err := os.ReadFile(filepath.Join(*rescoreDir, "results.json"))
		if err != nil {
			log.Fatal(err)
		}
		var res Results
		if err := json.Unmarshal(data, &res); err != nil {
			log.Fatal(err)
		}
		if err := writeOutputs(&res, labels, *rescoreDir); err != nil {
			log.Fatal(err)
		}
		fmt.Println("Re-scored", *rescoreDir)
		return
	}

	for _, l := range labels {
		if _, err := os.Stat(filepath.Join(*dir, "images", l.File)); err != nil {
			log.Fatalf("labels.csv lists %s, but images/%s is missing", l.File, l.File)
		}
	}

	client := &http.Client{Timeout: *timeout}
	started := time.Now()
	res := &Results{RunID: started.Format("20060102-150405"), API: *api, Repeats: *repeats, RunDay: started.Format("2006-01-02"), Started: started}

	type job struct {
		l   Label
		rep int
	}
	var jobs []job
	for rep := 1; rep <= *repeats; rep++ {
		for _, l := range labels {
			jobs = append(jobs, job{l, rep})
		}
	}
	fmt.Printf("Scanning %d images × %d = %d requests against %s…\n", len(labels), *repeats, len(jobs), *api)

	trials := make([]*Trial, len(jobs))
	var done int64
	sem := make(chan struct{}, *concurrency)
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			t := scan(client, *api, filepath.Join(*dir, "images", j.l.File), *timeout)
			t.File, t.Repeat = j.l.File, j.rep
			t.Score = scoreTrial(t, j.l, res.RunDay)
			trials[i] = t
			n := atomic.AddInt64(&done, 1)
			fmt.Printf("[%2d/%d] %-18s r%d  %-4s %5.1fs  amount:%v merchant:%v date:%s\n", n, len(jobs), j.l.File, j.rep,
				verdict(t), float64(t.LatencyMs)/1000, t.Score.AmountOK, t.Score.MerchantOK, dateText(t.Score.DateOK))
		}()
	}
	wg.Wait()
	res.Trials = trials

	outDir := filepath.Join(*dir, "results", res.RunID)
	if err := writeOutputs(res, labels, outDir); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("\nSummary: %s\n", filepath.Join(outDir, "summary.md"))
}

func scan(client *http.Client, api, path string, timeout time.Duration) *Trial {
	t := &Trial{}
	img, err := os.ReadFile(path)
	if err != nil {
		t.Status, t.Error = "error", err.Error()
		return t
	}
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	_ = w.WriteField("user_id", "eval-slipeval")
	part, _ := w.CreateFormFile("image", filepath.Base(path))
	_, _ = part.Write(img)
	_ = w.Close()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(api, "/")+"/api/scanner/process", &body)
	req.Header.Set("Content-Type", w.FormDataContentType())

	start := time.Now()
	resp, err := client.Do(req)
	t.LatencyMs = time.Since(start).Milliseconds()
	if err != nil {
		t.Status, t.Error = "error", err.Error()
		return t
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	var out struct {
		Merchant   string  `json:"merchant"`
		Amount     float64 `json:"amount"`
		Date       string  `json:"date"`
		Confidence float64 `json:"confidence"`
		Raw        string  `json:"raw_text"`
		Error      string  `json:"error"`
	}
	if jerr := json.Unmarshal(data, &out); jerr != nil || resp.StatusCode != http.StatusOK {
		t.Status = "error"
		t.Error = fmt.Sprintf("HTTP %d %s", resp.StatusCode, strings.TrimSpace(out.Error+" "+string(data[:min(len(data), 120)])))
		return t
	}
	t.Status = "ok"
	t.Merchant, t.Amount, t.Date, t.Confidence, t.Raw = out.Merchant, int64(math.Round(out.Amount)), out.Date, out.Confidence, out.Raw
	return t
}

func writeOutputs(res *Results, labels []Label, dir string) error {
	byFile := map[string]Label{}
	for _, l := range labels {
		byFile[l.File] = l
	}
	for _, t := range res.Trials {
		if l, ok := byFile[t.File]; ok {
			t.Score = scoreTrial(t, l, res.RunDay)
		}
	}
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
	return os.WriteFile(filepath.Join(dir, "summary.md"), []byte(summary(res, labels)), 0o644)
}

type agg struct {
	trials, ok, amount, merchant, dateN, date, all, fallback, defaulted, invented, errors int
	lat                                                                                   []int64
}

func (a *agg) add(t *Trial) {
	a.trials++
	if t.Status != "ok" {
		a.errors++
		return
	}
	a.ok++
	a.lat = append(a.lat, t.LatencyMs)
	s := t.Score
	if s.AmountOK {
		a.amount++
	}
	if s.MerchantOK {
		a.merchant++
	}
	if s.DateOK != nil {
		a.dateN++
		if *s.DateOK {
			a.date++
		}
	}
	if s.AllOK {
		a.all++
	}
	if s.Fallback {
		a.fallback++
	}
	if s.DateDefaulted {
		a.defaulted++
	}
	if s.DateInvented {
		a.invented++
	}
}

// Summary tables carry file names, kinds and whether each field was right — never
// the names read from the slips — so summary.md is safe to copy into the docs.
func summary(res *Results, labels []Label) string {
	var b strings.Builder
	byFile := map[string]Label{}
	unverified := 0
	for _, l := range labels {
		byFile[l.File] = l
		if !l.Verified {
			unverified++
		}
	}
	fmt.Fprintf(&b, "# Slip scanner evaluation — run %s\n\n", res.RunID)
	fmt.Fprintf(&b, "Gemini Vision via `POST /api/scanner/process` · %d images × %d scans · run day %s\n\n", len(labels), res.Repeats, res.RunDay)
	if unverified > 0 {
		fmt.Fprintf(&b, "> ⚠️ %d of %d labels are not marked verified — treat these numbers as provisional.\n\n", unverified, len(labels))
	}

	groups := map[string]*agg{"eslip": {}, "receipt": {}, "all": {}}
	orient := map[string]*agg{}
	var confRight, confWrong []float64
	hi, hiAll, lo, loAll := 0, 0, 0, 0
	for _, t := range res.Trials {
		l := byFile[t.File]
		for _, key := range []string{l.Kind, "all"} {
			if g, ok := groups[key]; ok {
				g.add(t)
			}
		}
		if orient[l.Orientation] == nil {
			orient[l.Orientation] = &agg{}
		}
		orient[l.Orientation].add(t)
		if t.Status == "ok" {
			if t.Score.AllOK {
				confRight = append(confRight, t.Confidence)
			} else {
				confWrong = append(confWrong, t.Confidence)
			}
			if t.Confidence >= 0.9 {
				hi++
				if t.Score.AllOK {
					hiAll++
				}
			} else {
				lo++
				if t.Score.AllOK {
					loAll++
				}
			}
		}
	}

	b.WriteString("## T1 · Field accuracy (per scan)\n\n| | Scans | Amount | Merchant | Date | All fields right | Fallback | Printed date replaced by today | No printed date: invented one | p50 / p95 | Errors |\n|---|---|---|---|---|---|---|---|---|---|---|\n")
	for _, key := range []string{"eslip", "receipt", "all"} {
		g := groups[key]
		name := map[string]string{"eslip": "E-slips (K PLUS)", "receipt": "Paper receipts", "all": "**All**"}[key]
		fmt.Fprintf(&b, "| %s | %d | %s | %s | %s | %s | %d | %d | %d | %s / %s | %d |\n", name, g.trials,
			pct(g.amount, g.ok), pct(g.merchant, g.ok), pct(g.date, g.dateN), pct(g.all, g.ok),
			g.fallback, g.defaulted, g.invented, pctl(g.lat, 50), pctl(g.lat, 95), g.errors)
	}

	b.WriteString("\n## T2 · All fields right, by how the image was taken\n\n| Orientation | Scans | All fields right |\n|---|---|---|\n")
	var keys []string
	for k := range orient {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Fprintf(&b, "| %s | %d | %s |\n", k, orient[k].trials, pct(orient[k].all, orient[k].ok))
	}

	b.WriteString("\n## T3 · Does confidence predict mistakes?\n\n| | Value |\n|---|---|\n")
	fmt.Fprintf(&b, "| Mean confidence when all fields right / not | %.2f / %.2f |\n", mean(confRight), mean(confWrong))
	fmt.Fprintf(&b, "| All fields right when confidence ≥ 0.9 | %s (%d scans) |\n", pct(hiAll, hi), hi)
	fmt.Fprintf(&b, "| All fields right when confidence < 0.9 | %s (%d scans) |\n", pct(loAll, lo), lo)

	b.WriteString("\n## T4 · Per image (✓ right, ✗ wrong; a date label of – means no date is printed, so the scanner should return the scan day; one mark per scan)\n\n| File | Kind | Orientation | Notes | Amount label → read | Date label → read | Merchant | All |\n|---|---|---|---|---|---|---|---|\n")
	perFile := map[string][]*Trial{}
	for _, t := range res.Trials {
		perFile[t.File] = append(perFile[t.File], t)
	}
	stable, stableN := 0, 0
	for _, l := range labels {
		ts := perFile[l.File]
		sort.Slice(ts, func(i, j int) bool { return ts[i].Repeat < ts[j].Repeat })
		var amounts, dates, merch, all []string
		same := true
		for i, t := range ts {
			if t.Status != "ok" {
				amounts, dates, merch, all = append(amounts, "err"), append(dates, "err"), append(merch, "err"), append(all, "✗")
				same = false
				continue
			}
			amounts = append(amounts, fmt.Sprint(t.Amount))
			dates = append(dates, t.Date)
			merch = append(merch, mark(t.Score.MerchantOK))
			all = append(all, mark(t.Score.AllOK))
			if i > 0 && (t.Amount != ts[0].Amount || t.Date != ts[0].Date || normalize(t.Merchant) != normalize(ts[0].Merchant)) {
				same = false
			}
		}
		if len(ts) > 1 {
			stableN++
			if same {
				stable++
			}
		}
		labelDate := l.Date
		if labelDate == "" {
			labelDate = "–"
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s | %s → %s | %s → %s | %s | %s |\n", l.File, l.Kind, l.Orientation, l.Notes,
			trimAmount(l.Amount), strings.Join(amounts, ", "), labelDate, strings.Join(dates, ", "), strings.Join(merch, " "), strings.Join(all, " "))
	}
	fmt.Fprintf(&b, "\nIdentical output on every scan: %s of images.\n", pct(stable, stableN))

	all, es, rc := groups["all"], groups["eslip"], groups["receipt"]
	b.WriteString("\n## SLIDE_VALUES\n\n```\n")
	fmt.Fprintf(&b, "IMAGES=%d\nSCANS=%d\nALL_FIELDS=%s\nAMOUNT=%s\nMERCHANT=%s\nDATE=%s\nESLIP_ALL=%s\nRECEIPT_ALL=%s\nESLIP_AMOUNT=%s\nRECEIPT_AMOUNT=%s\nFALLBACK=%d\nDATE_DEFAULTED=%d\nDATE_INVENTED=%d\nSTABLE=%s\nP50=%s\nUNVERIFIED=%d\n",
		len(labels), all.trials, pct(all.all, all.ok), pct(all.amount, all.ok), pct(all.merchant, all.ok), pct(all.date, all.dateN),
		pct(es.all, es.ok), pct(rc.all, rc.ok), pct(es.amount, es.ok), pct(rc.amount, rc.ok), all.fallback, all.defaulted, all.invented, pct(stable, stableN), pctl(all.lat, 50), unverified)
	b.WriteString("```\n")
	return b.String()
}

func verdict(t *Trial) string {
	if t.Status != "ok" {
		return "ERR"
	}
	if t.Score.AllOK {
		return "PASS"
	}
	return "fail"
}

func dateText(ok *bool) string {
	if ok == nil {
		return "n/a"
	}
	return fmt.Sprint(*ok)
}

func mark(ok bool) string {
	if ok {
		return "✓"
	}
	return "✗"
}

func pct(k, n int) string {
	if n == 0 {
		return "–"
	}
	return fmt.Sprintf("%.0f%% (%d/%d)", 100*float64(k)/float64(n), k, n)
}

func pctl(v []int64, p float64) string {
	if len(v) == 0 {
		return "–"
	}
	s := append([]int64(nil), v...)
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	i := int(math.Ceil(p/100*float64(len(s)))) - 1
	if i < 0 {
		i = 0
	}
	return fmt.Sprintf("%.1fs", float64(s[i])/1000)
}

func mean(v []float64) float64 {
	if len(v) == 0 {
		return 0
	}
	var sum float64
	for _, x := range v {
		sum += x
	}
	return sum / float64(len(v))
}

func trimAmount(v float64) string {
	if v == math.Trunc(v) {
		return fmt.Sprintf("%.0f", v)
	}
	return fmt.Sprintf("%.2f", v)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
