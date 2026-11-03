package routes

import (
	"testing"
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/insights"
	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"github.com/SmartFin-App/smartfin-backend/internal/summaries"
)

func seedTxs() []models.Transaction {
	var out []models.Transaction
	for _, r := range demoRows {
		out = append(out, demoTransaction("demo", r, time.Now()))
	}
	return out
}

// The coach evaluation asks about the seeded data, and some of its expected
// answers depend on the data's shape rather than being recomputed.
func TestSeedShapeTheEvaluationReliesOn(t *testing.T) {
	txs := seedTxs()
	if len(txs) != 53 {
		t.Errorf("cmd/eval expects 53 seeded expenses (seededTxCount), got %d", len(txs))
	}
	months := map[string]int64{}
	dec := map[string]int64{}
	for _, tx := range txs {
		m := summaries.StringOf(tx.Date)
		months[m] += tx.Amount
		if m == "2025-12" {
			dec[tx.Category] += tx.Amount
		}
	}
	for m, v := range months {
		if m != "2026-01" && v >= months["2026-01"] {
			t.Errorf("L/A2 expect January to be the most expensive month; %s has ฿%d vs ฿%d", m, v, months["2026-01"])
		}
	}
	for cat, v := range dec {
		if cat != "Shopping" && v >= dec["Shopping"] {
			t.Errorf("L4 expects Shopping to be December's biggest category; %s has ฿%d", cat, v)
		}
	}
}

// April is what the coach shows when asked about bad expenses.
func TestSeedAprilHasSpendingToReview(t *testing.T) {
	r, err := insights.Analyze(seedTxs(), nil, "2026-04")
	if err != nil {
		t.Fatal(err)
	}
	if len(r.UnusualPurchases) != 1 || r.UnusualPurchases[0].Merchant != "Thai Ticket Major" {
		t.Errorf("want the concert ticket flagged, got %+v", r.UnusualPurchases)
	}
	habits := map[string]int64{}
	for _, h := range r.FrequentSmallPurchases {
		habits[h.Merchant] = h.Total
	}
	if habits["Starbucks Coffee"] != 1450 || habits["Line MAN"] != 1640 || len(habits) != 2 {
		t.Errorf("want Starbucks ฿1,450 and Line MAN ฿1,640, got %v", habits)
	}
	if len(r.GrowingCategories) != 2 {
		t.Errorf("want Entertainment and Food flagged as growing, got %+v", r.GrowingCategories)
	}
}
