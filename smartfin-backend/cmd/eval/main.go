// Command eval scores the SmartFin AI coach against answers that can be checked.
//
// It creates throwaway eval users through the API (profile, the 47 seeded demo
// transactions and three bills), asks 30 scripted questions, and scores every
// answer by rule against figures recomputed from MongoDB. The agentic coach is
// compared with two baselines on the same model: no retrieval, and one-shot RAG
// with the user's complete records pasted into the prompt.
//
// Run it from smartfin-backend/ against a server started with the trace enabled:
//
//	PORT=3001 COACH_EVAL_TRACE=1 go run cmd/main.go
//	go run ./cmd/eval -repeats 3
//
// It never calls the admin reset routes. Eval users are prefixed "eval-<run>-" and
// deleted through the API's own account deletion when the run ends.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/SmartFin-App/smartfin-backend/config"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
	"github.com/google/generative-ai-go/genai"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"google.golang.org/api/option"
)

var allSystems = []string{"agentic", "oneshot", "noretrieval"}

const (
	seededIncome  = 35000
	seededBudget  = 15000
	emptyIncome   = 28000
	emptyBudget   = 12000
	seededTxCount = 47
)

type billSpec struct {
	Name     string
	Amount   int64
	Category string
	Offset   int // days from the run day
}

// One overdue, one due tomorrow, one later — so "overdue" and "next 7 days"
// questions have exactly one right answer.
var evalBills = []billSpec{
	{"AIS Fibre", 649, "Bills", -2},
	{"Netflix", 419, "Entertainment", 1},
	{"Condo Rent", 8500, "Bills", 10},
}

type userPlan struct {
	UID   string
	Empty bool
}

func main() {
	apiURL := flag.String("api", envOr("EVAL_API", "http://localhost:3001"), "SmartFin API started with COACH_EVAL_TRACE=1")
	repeats := flag.Int("repeats", 3, "runs per case per system")
	concurrency := flag.Int("concurrency", 3, "questions answered in parallel")
	systemsFlag := flag.String("systems", strings.Join(allSystems, ","), "systems to evaluate (agentic,oneshot,noretrieval)")
	casesFlag := flag.String("cases", "", "comma-separated case IDs (default: all)")
	outDir := flag.String("out", "eval-results", "output directory")
	timeout := flag.Duration("timeout", 60*time.Second, "per-question timeout")
	keep := flag.Bool("keep", false, "keep the eval users after the run")
	rescoreDir := flag.String("rescore", "", "re-score an existing run directory with the current rules")
	cleanup := flag.Bool("cleanup", false, "delete eval users left behind by an interrupted run")
	flag.Parse()
	log.SetFlags(0)

	if *rescoreDir != "" {
		if err := rescore(*rescoreDir); err != nil {
			log.Fatalf("rescore: %v", err)
		}
		fmt.Println("Re-scored", *rescoreDir)
		return
	}

	cases, err := selectCases(*casesFlag)
	if err != nil {
		log.Fatal(err)
	}
	systems, err := selectSystems(*systemsFlag)
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	config.ConnectDB()
	api := NewClient(*apiURL, *timeout)
	if err := api.Health(ctx); err != nil {
		log.Fatalf("API not reachable at %s (%v).\nStart one with: PORT=3001 COACH_EVAL_TRACE=1 go run cmd/main.go", *apiURL, err)
	}

	if *cleanup {
		n, err := cleanupEvalUsers(ctx, api)
		if err != nil {
			log.Fatalf("cleanup: %v", err)
		}
		fmt.Printf("Deleted %d leftover eval users.\n", n)
		return
	}

	key := os.Getenv("GEMINI_API_KEY")
	if key == "" {
		log.Fatal("GEMINI_API_KEY is not set (it is read from smartfin-backend/.env)")
	}
	gem, err := genai.NewClient(ctx, option.WithAPIKey(key))
	if err != nil {
		log.Fatalf("Gemini client: %v", err)
	}
	defer gem.Close()
	pctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	if _, err := askGemini(pctx, gem, "Reply with the single word OK.", nil, "ping"); err != nil {
		cancel()
		log.Fatalf("Gemini preflight failed: %v", err)
	}
	cancel()

	started := time.Now()
	runID := started.In(summaries.Zone).Format("20060102-150405")
	prefix := "eval-" + runID + "-"
	runner := &Runner{api: api, gemini: gem, prefix: prefix, timeout: *timeout, prompts: map[string]string{}}

	// ── Setup ──────────────────────────────────────────────────────────────
	refUID := prefix + "ref"
	plans := []userPlan{{UID: refUID}}
	if contains(systems, "agentic") {
		for rep := 1; rep <= *repeats; rep++ {
			for _, c := range cases {
				plans = append(plans, userPlan{UID: runner.uidFor(c, rep), Empty: c.NoData})
			}
		}
	}
	fmt.Printf("Run %s: creating %d eval users…\n", runID, len(plans))
	created, setupErr := setupUsers(ctx, api, plans, started)
	teardown := func() {
		if *keep {
			fmt.Println("Keeping eval users (-keep). Remove them later with -cleanup.")
			return
		}
		deleteUsers(ctx, api, created, prefix)
	}
	if setupErr != nil {
		teardown()
		log.Fatalf("setup failed: %v", setupErr)
	}

	refData, err := LoadUserData(ctx, refUID, started)
	if err != nil {
		teardown()
		log.Fatal(err)
	}
	seeded := BuildTruth(refData)
	emptyData := UserData{Name: "Eval User", Income: emptyIncome, Budget: emptyBudget}
	empty := BuildTruth(emptyData)
	seededBase, emptyBase := seeded.AllowedBase(refData.Txs), empty.AllowedBase(nil)

	res := &Results{Resolved: map[string][]int64{}, Allowed: map[string][]int64{}}
	var ids []string
	for _, c := range cases {
		ids = append(ids, c.ID)
		truth, base := seeded, seededBase
		if c.NoData {
			truth, base = empty, emptyBase
		}
		for _, spec := range c.Required {
			v, err := truth.Resolve(spec)
			if err != nil {
				teardown()
				log.Fatalf("case %s: %v", c.ID, err)
			}
			res.Resolved[c.ID] = append(res.Resolved[c.ID], v)
		}
		res.Allowed[c.ID] = CaseAllowed(c, truth, base)
	}
	runner.prompts["noretrieval|seeded"] = NoRetrievalPrompt(started)
	runner.prompts["noretrieval|empty"] = runner.prompts["noretrieval|seeded"]
	runner.prompts["oneshot|seeded"] = OneShotPrompt(refData, seeded, started)
	runner.prompts["oneshot|empty"] = OneShotPrompt(emptyData, empty, started)

	res.Meta = Meta{
		RunID: runID, GitSHA: gitSHA(), Model: modelName, Temperature: temperature,
		Repeats: *repeats, Concurrency: *concurrency, Systems: systems, Cases: ids, API: *apiURL,
		ThaiDateStart: summaries.DueDateString(started), Started: started,
	}

	// ── Run ────────────────────────────────────────────────────────────────
	type job struct {
		system string
		c      Case
		rep    int
	}
	var jobs []job
	for rep := 1; rep <= *repeats; rep++ {
		for _, c := range cases {
			for _, sys := range systems {
				jobs = append(jobs, job{sys, c, rep})
			}
		}
	}
	fmt.Printf("Asking %d questions (%d cases × %d systems × %d repeats, %d at a time)…\n",
		len(jobs), len(cases), len(systems), *repeats, *concurrency)

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
			t := runner.runTrial(ctx, j.system, j.c, j.rep)
			t.Score = ScoreTrial(j.c, t, res.Resolved[j.c.ID], res.Allowed[j.c.ID])
			trials[i] = t
			n := atomic.AddInt64(&done, 1)
			verdict, why := "PASS", ""
			if !t.Score.Pass {
				verdict = "fail"
				if len(t.Score.FailReasons) > 0 {
					why = t.Score.FailReasons[0]
				}
			}
			fmt.Printf("[%3d/%d] %-11s %-3s r%d  %-4s %5.1fs  %s\n",
				n, len(jobs), j.system, j.c.ID, j.rep, verdict, float64(t.LatencyMs)/1000, truncate(why, 90))
		}()
	}
	wg.Wait()

	res.Trials = trials
	res.Meta.Finished = time.Now()
	res.Meta.ThaiDateEnd = summaries.DueDateString(res.Meta.Finished)
	if res.Meta.ThaiDateEnd != res.Meta.ThaiDateStart {
		res.Meta.Warnings = append(res.Meta.Warnings, "The Thai date changed during the run, so bill due-date answers late in the run may not match ground truth.")
	}

	dir := filepath.Join(*outDir, runID)
	if err := writeOutputs(res, dir); err != nil {
		log.Printf("writing results failed: %v", err)
	}

	// ── Teardown ───────────────────────────────────────────────────────────
	teardown()
	if !*keep {
		if n, err := residue(ctx, prefix); err != nil || n > 0 {
			fmt.Printf("WARNING: %d eval records remain for %s (err: %v). Run with -cleanup.\n", n, prefix, err)
		} else {
			fmt.Println("All eval users deleted.")
		}
	}

	fmt.Printf("\nShared questions (%d cases × %d repeats):\n", countScope(cases, "shared"), *repeats)
	for _, sys := range systems {
		a := aggregate(res.Trials, sys, func(t *Trial) bool { return t.Scope == "shared" })
		fmt.Printf("  %-14s pass %s (%s)  numeric accuracy %s  p50 %s\n",
			systemLabel[sys], pct(a.pass, a.n), frac(a.pass, a.n), pct(a.reqHit, a.reqTotal), percentile(a.lat, 50))
	}
	fmt.Printf("\nSummary: %s\n", filepath.Join(dir, "summary.md"))
}

func setupUsers(ctx context.Context, api *Client, plans []userPlan, now time.Time) ([]string, error) {
	var (
		mu       sync.Mutex
		created  []string
		firstErr error
		wg       sync.WaitGroup
	)
	sem := make(chan struct{}, 8)
	for _, p := range plans {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			// Recorded before creation, so teardown also covers a half-created user.
			mu.Lock()
			created = append(created, p.UID)
			mu.Unlock()
			if err := setupUser(ctx, api, p, now); err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	return created, firstErr
}

func setupUser(ctx context.Context, api *Client, p userPlan, now time.Time) error {
	sctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	income, budget := int64(seededIncome), int64(seededBudget)
	if p.Empty {
		income, budget = emptyIncome, emptyBudget
	}
	if err := api.CreateUser(sctx, p.UID, income, budget); err != nil {
		return err
	}
	if p.Empty {
		return nil
	}
	if err := api.Seed(sctx, p.UID); err != nil {
		return err
	}
	day := summaries.DateOf(now)
	for _, b := range evalBills {
		due := summaries.DueDateString(day.AddDate(0, 0, b.Offset))
		if err := api.CreateBill(sctx, p.UID, b.Name, b.Amount, b.Category, due); err != nil {
			return err
		}
	}
	// Seeding is not idempotent: check the user holds exactly one copy.
	n, err := config.GetCollection("transactions").CountDocuments(sctx, bson.M{"user_id": p.UID})
	if err != nil {
		return err
	}
	if n != seededTxCount {
		return fmt.Errorf("%s: expected %d seeded transactions, found %d", p.UID, seededTxCount, n)
	}
	s, err := config.GetCollection("subscriptions").CountDocuments(sctx, bson.M{"user_id": p.UID})
	if err != nil {
		return err
	}
	if s != int64(len(evalBills)) {
		return fmt.Errorf("%s: expected %d bills, found %d", p.UID, len(evalBills), s)
	}
	return nil
}

func deleteUsers(ctx context.Context, api *Client, uids []string, prefix string) {
	var wg sync.WaitGroup
	var failed int64
	sem := make(chan struct{}, 8)
	for _, uid := range uids {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			dctx, cancel := context.WithTimeout(ctx, 30*time.Second)
			defer cancel()
			if err := api.DeleteUser(dctx, uid, prefix); err != nil {
				atomic.AddInt64(&failed, 1)
				log.Printf("delete %s: %v", uid, err)
			}
		}()
	}
	wg.Wait()
	fmt.Printf("Deleted %d eval users (%d failed).\n", int64(len(uids))-failed, failed)
}

var evalOwnerFields = map[string]string{
	"users": "firebase_uid", "transactions": "user_id", "subscriptions": "user_id",
	"chat_messages": "user_id", "monthly_summaries": "user_id",
}

// residue counts records still owned by this run's eval users.
func residue(ctx context.Context, prefix string) (int64, error) {
	var total int64
	for col, field := range evalOwnerFields {
		n, err := config.GetCollection(col).CountDocuments(ctx, bson.M{field: bson.M{"$regex": "^" + regexp.QuoteMeta(prefix)}})
		if err != nil {
			return total, err
		}
		total += n
	}
	return total, nil
}

// cleanupEvalUsers finds every uid starting with "eval-" in any owned collection
// and deletes it through the API.
func cleanupEvalUsers(ctx context.Context, api *Client) (int, error) {
	uids := map[string]bool{}
	for col, field := range evalOwnerFields {
		cur, err := config.GetCollection(col).Find(ctx, bson.M{field: bson.M{"$regex": "^eval-"}},
			options.Find().SetProjection(bson.M{field: 1}))
		if err != nil {
			return 0, err
		}
		var docs []bson.M
		if err := cur.All(ctx, &docs); err != nil {
			return 0, err
		}
		for _, d := range docs {
			if v, ok := d[field].(string); ok {
				uids[v] = true
			}
		}
	}
	list := make([]string, 0, len(uids))
	for uid := range uids {
		list = append(list, uid)
	}
	deleteUsers(ctx, api, list, "eval-")
	return len(list), nil
}

func rescore(dir string) error {
	path := filepath.Join(dir, "results.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var res Results
	if err := json.Unmarshal(data, &res); err != nil {
		return err
	}
	orig := filepath.Join(dir, "results.orig.json")
	if _, err := os.Stat(orig); os.IsNotExist(err) {
		if err := os.WriteFile(orig, data, 0o644); err != nil {
			return err
		}
	}
	byID := casesByID()
	for _, t := range res.Trials {
		c, ok := byID[t.CaseID]
		if !ok {
			continue
		}
		t.Category, t.Scope = c.Category, c.Scope
		t.Score = ScoreTrial(c, t, res.Resolved[t.CaseID], res.Allowed[t.CaseID])
	}
	return writeOutputs(&res, dir)
}

func selectCases(flagValue string) ([]Case, error) {
	if strings.TrimSpace(flagValue) == "" {
		return allCases, nil
	}
	byID := casesByID()
	var out []Case
	for _, id := range strings.Split(flagValue, ",") {
		c, ok := byID[strings.ToUpper(strings.TrimSpace(id))]
		if !ok {
			return nil, fmt.Errorf("unknown case %q", id)
		}
		out = append(out, c)
	}
	return out, nil
}

func selectSystems(flagValue string) ([]string, error) {
	var out []string
	for _, s := range strings.Split(flagValue, ",") {
		s = strings.TrimSpace(s)
		if !contains(allSystems, s) {
			return nil, fmt.Errorf("unknown system %q (use %s)", s, strings.Join(allSystems, ","))
		}
		out = append(out, s)
	}
	return out, nil
}

func countScope(cases []Case, scope string) int {
	n := 0
	for _, c := range cases {
		if c.Scope == scope {
			n++
		}
	}
	return n
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func gitSHA() string {
	out, err := exec.Command("git", "rev-parse", "--short", "HEAD").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}
