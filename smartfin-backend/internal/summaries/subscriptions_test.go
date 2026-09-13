package summaries

import (
	"testing"
	"time"
)

// A fixed clock: Sunday 13 Sep 2026, 15:00 Thai time.
var subNow = time.Date(2026, 9, 13, 15, 0, 0, 0, Zone)

func dueOn(y int, m time.Month, d int) time.Time {
	return time.Date(y, m, d, 0, 0, 0, 0, Zone)
}

func TestAdvanceDue(t *testing.T) {
	cases := []struct {
		name   string
		due    time.Time
		cycle  string
		anchor int
		want   time.Time
	}{
		{"weekly", dueOn(2026, 9, 13), CycleWeekly, 13, dueOn(2026, 9, 20)},
		{"weekly across a month", dueOn(2026, 9, 28), CycleWeekly, 28, dueOn(2026, 10, 5)},
		{"weekly across a year", dueOn(2026, 12, 29), CycleWeekly, 29, dueOn(2027, 1, 5)},
		{"monthly", dueOn(2026, 9, 13), CycleMonthly, 13, dueOn(2026, 10, 13)},
		{"monthly from Jan 31 clamps to Feb 28", dueOn(2026, 1, 31), CycleMonthly, 31, dueOn(2026, 2, 28)},
		{"monthly returns to the anchor after a short month", dueOn(2026, 2, 28), CycleMonthly, 31, dueOn(2026, 3, 31)},
		{"monthly into a leap February", dueOn(2028, 1, 31), CycleMonthly, 31, dueOn(2028, 2, 29)},
		{"monthly December to January", dueOn(2026, 12, 15), CycleMonthly, 15, dueOn(2027, 1, 15)},
		{"missing anchor falls back to the due day", dueOn(2026, 1, 31), CycleMonthly, 0, dueOn(2026, 2, 28)},
		{"yearly", dueOn(2026, 9, 13), CycleYearly, 13, dueOn(2027, 9, 13)},
		{"yearly from a leap day", dueOn(2028, 2, 29), CycleYearly, 29, dueOn(2029, 2, 28)},
		{"yearly back onto a leap day", dueOn(2031, 2, 28), CycleYearly, 29, dueOn(2032, 2, 29)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := AdvanceDue(tc.due, tc.cycle, tc.anchor)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !got.Equal(tc.want) {
				t.Errorf("got %s, want %s", DueDateString(got), DueDateString(tc.want))
			}
			if got.Location() != Zone {
				t.Errorf("location = %v, want Zone", got.Location())
			}
		})
	}
}

func TestAdvanceDueChainsWithoutDrifting(t *testing.T) {
	d := dueOn(2026, 1, 30)
	want := []time.Time{dueOn(2026, 2, 28), dueOn(2026, 3, 30), dueOn(2026, 4, 30)}
	for i, w := range want {
		next, err := AdvanceDue(d, CycleMonthly, 30)
		if err != nil {
			t.Fatal(err)
		}
		if !next.Equal(w) {
			t.Fatalf("step %d: got %s, want %s", i+1, DueDateString(next), DueDateString(w))
		}
		d = next
	}
}

// MongoDB returns the stored midnight as a UTC instant on the previous day. The
// advance must still work from the Thai calendar day.
func TestAdvanceDueFromAUTCInstant(t *testing.T) {
	stored := time.Date(2026, 9, 12, 17, 0, 0, 0, time.UTC) // 13 Sep 00:00 Thai time
	got, err := AdvanceDue(stored, CycleMonthly, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(dueOn(2026, 10, 13)) {
		t.Errorf("got %s, want 2026-10-13", DueDateString(got))
	}
	if got.Location() != Zone || got.Hour() != 0 {
		t.Errorf("got %v, want midnight in Zone", got)
	}
}

func TestAdvanceDueRejectsAnUnknownCycle(t *testing.T) {
	if _, err := AdvanceDue(subNow, "daily", 13); err == nil {
		t.Error("expected an error for an unknown cycle")
	}
}

func TestDaysUntil(t *testing.T) {
	cases := []struct {
		name string
		due  time.Time
		now  time.Time
		want int
	}{
		{"due today", dueOn(2026, 9, 13), subNow, 0},
		{"due tomorrow", dueOn(2026, 9, 14), subNow, 1},
		{"due yesterday", dueOn(2026, 9, 12), subNow, -1},
		{"a week away", dueOn(2026, 9, 20), subNow, 7},
		{"due given as a UTC instant", time.Date(2026, 9, 13, 17, 0, 0, 0, time.UTC), subNow, 1},
		{"just after Thai midnight while UTC is still the day before", dueOn(2026, 9, 14), time.Date(2026, 9, 13, 17, 30, 0, 0, time.UTC), 0},
		{"across the new year", dueOn(2027, 1, 1), time.Date(2026, 12, 31, 23, 0, 0, 0, Zone), 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := DaysUntil(tc.due, tc.now); got != tc.want {
				t.Errorf("got %d, want %d", got, tc.want)
			}
		})
	}
}

func TestDueStatus(t *testing.T) {
	cases := []struct {
		days   int
		active bool
		want   string
	}{
		{-1, true, StatusOverdue},
		{0, true, StatusDueToday},
		{1, true, StatusDueSoon},
		{7, true, StatusDueSoon},
		{8, true, StatusUpcoming},
		{-5, false, StatusPaused},
	}
	for _, tc := range cases {
		if got := DueStatus(tc.days, tc.active); got != tc.want {
			t.Errorf("DueStatus(%d, %v) = %q, want %q", tc.days, tc.active, got, tc.want)
		}
	}
}

func TestDueLabel(t *testing.T) {
	cases := map[string]time.Time{
		"Today":     dueOn(2026, 9, 13),
		"Tomorrow":  dueOn(2026, 9, 14),
		"Yesterday": dueOn(2026, 9, 12),
		"Oct 14":    dueOn(2026, 10, 14),
	}
	for want, due := range cases {
		if got := DueLabel(due, subNow); got != want {
			t.Errorf("DueLabel(%s) = %q, want %q", DueDateString(due), got, want)
		}
	}
}

func TestMonthlyEquivalent(t *testing.T) {
	cases := []struct {
		amount int64
		cycle  string
		want   int64
	}{
		{419, CycleMonthly, 419},
		{100, CycleWeekly, 433},
		{150, CycleWeekly, 650},
		{125, CycleWeekly, 542},
		{1200, CycleYearly, 100},
		{1990, CycleYearly, 166},
		{6, CycleYearly, 1},
		{5, CycleYearly, 0},
		{500, "daily", 0},
	}
	for _, tc := range cases {
		if got := MonthlyEquivalent(tc.amount, tc.cycle); got != tc.want {
			t.Errorf("MonthlyEquivalent(%d, %q) = %d, want %d", tc.amount, tc.cycle, got, tc.want)
		}
	}
}

func TestParseDueDate(t *testing.T) {
	got, err := ParseDueDate("2026-09-14")
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(time.Date(2026, 9, 13, 17, 0, 0, 0, time.UTC)) {
		t.Errorf("a plain date must be a Thai calendar day, got %v", got.UTC())
	}

	if _, err := ParseDueDate(" 2026-09-14 "); err != nil {
		t.Errorf("surrounding spaces should be ignored: %v", err)
	}

	stamp, err := ParseDueDate("2026-09-13T20:00:00Z")
	if err != nil {
		t.Fatal(err)
	}
	if !stamp.Equal(dueOn(2026, 9, 14)) {
		t.Errorf("a timestamp must reduce to its Thai day, got %s", DueDateString(stamp))
	}

	for _, bad := range []string{"2026-02-30", "14/09/2026", "", "next month"} {
		if _, err := ParseDueDate(bad); err == nil {
			t.Errorf("ParseDueDate(%q) should fail", bad)
		}
	}
}

func TestValidCycle(t *testing.T) {
	for _, c := range []string{CycleWeekly, CycleMonthly, CycleYearly} {
		if !ValidCycle(c) {
			t.Errorf("%q should be valid", c)
		}
	}
	for _, c := range []string{"", "daily", "Monthly"} {
		if ValidCycle(c) {
			t.Errorf("%q should be invalid", c)
		}
	}
}
