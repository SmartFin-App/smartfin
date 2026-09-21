package summaries

import (
	"testing"
	"time"
)

func TestBoundsRejectsMalformedMonths(t *testing.T) {
	for _, month := range []string{"", "2026", "2026-", "2026-4", "26-04", "2026-13", "2026-00", "abcd-ef", "2026-04-01"} {
		if _, _, err := Bounds(month); err == nil {
			t.Errorf("Bounds(%q) accepted a malformed month", month)
		}
	}
}

func TestBoundsIsAThaiLocalHalfOpenWindow(t *testing.T) {
	start, end, err := Bounds("2026-04")
	if err != nil {
		t.Fatalf("Bounds returned error: %v", err)
	}
	if got := start.Format(time.RFC3339); got != "2026-04-01T00:00:00+07:00" {
		t.Errorf("start = %s, want 2026-04-01T00:00:00+07:00", got)
	}
	if got := end.Format(time.RFC3339); got != "2026-05-01T00:00:00+07:00" {
		t.Errorf("end = %s, want 2026-05-01T00:00:00+07:00", got)
	}
}

// A Bangkok user's 06:00 expense on the 1st is stored as 23:00Z the previous day.
// A UTC window filed it under the previous month; the ICT window must not.
func TestBoundsCoversEarlyMorningBangkokTransactions(t *testing.T) {
	start, end, err := Bounds("2026-04")
	if err != nil {
		t.Fatalf("Bounds returned error: %v", err)
	}
	stored := time.Date(2026, 3, 31, 23, 0, 0, 0, time.UTC) // 06:00 on 1 Apr in Bangkok
	if stored.Before(start) || !stored.Before(end) {
		t.Errorf("%s should fall inside the April window [%s, %s)", stored, start, end)
	}
}

// Date-only transactions are stored at UTC midnight; they must land in their own month.
func TestBoundsCoversUTCMidnightDateOnlyTransactions(t *testing.T) {
	start, end, err := Bounds("2026-04")
	if err != nil {
		t.Fatalf("Bounds returned error: %v", err)
	}
	for _, day := range []int{1, 15, 30} {
		stored := time.Date(2026, 4, day, 0, 0, 0, 0, time.UTC)
		if stored.Before(start) || !stored.Before(end) {
			t.Errorf("%s should fall inside the April window", stored)
		}
	}
	if outside := time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC); outside.Before(end) {
		t.Errorf("1 May should not fall inside the April window")
	}
}

func TestStringOfUsesThaiLocalTime(t *testing.T) {
	// 23:30Z on 31 March is already April in Bangkok.
	if got := StringOf(time.Date(2026, 3, 31, 23, 30, 0, 0, time.UTC)); got != "2026-04" {
		t.Errorf("StringOf = %q, want 2026-04", got)
	}
	if got := StringOf(time.Date(2026, 4, 9, 12, 0, 0, 0, time.UTC)); got != "2026-04" {
		t.Errorf("StringOf = %q, want 2026-04", got)
	}
}

// GetSummaryHistory anchors to the first of the month before subtracting. Doing it
// off the raw clock on the 31st skips 30-day months and duplicates others.
func TestMonthAnchorWalkbackHasNoGapsOrDuplicates(t *testing.T) {
	now := time.Date(2026, 8, 31, 10, 0, 0, 0, Zone)
	anchor := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, Zone)

	var got []string
	seen := map[string]bool{}
	for i := 0; i < 6; i++ {
		m := StringOf(anchor.AddDate(0, -i, 0))
		if seen[m] {
			t.Errorf("month %s appeared twice in the 6-month walk-back", m)
		}
		seen[m] = true
		got = append(got, m)
	}

	want := []string{"2026-08", "2026-07", "2026-06", "2026-05", "2026-04", "2026-03"}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("walk-back[%d] = %s, want %s (full: %v)", i, got[i], want[i], got)
		}
	}
}

func TestBaht(t *testing.T) {
	cases := map[int64]string{
		0:       "฿0",
		999:     "฿999",
		1000:    "฿1,000",
		15000:   "฿15,000",
		1234567: "฿1,234,567",
		-1500:   "-฿1,500",
		-999:    "-฿999",
		-100000: "-฿100,000",
	}
	for in, want := range cases {
		if got := Baht(in); got != want {
			t.Errorf("Baht(%d) = %q, want %q", in, got, want)
		}
	}
}
