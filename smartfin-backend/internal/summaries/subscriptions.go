package summaries

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// Billing cycles a tracked subscription or bill can repeat on.
const (
	CycleWeekly  = "weekly"
	CycleMonthly = "monthly"
	CycleYearly  = "yearly"
)

// DueSoonDays is how far ahead a bill counts as "due soon" — the window the
// dashboard card, the tracker's middle section and the status badge all share.
const DueSoonDays = 7

// Statuses a bill can be in, derived from its due date on every read.
const (
	StatusPaused   = "paused"
	StatusOverdue  = "overdue"
	StatusDueToday = "due_today"
	StatusDueSoon  = "due_soon"
	StatusUpcoming = "upcoming"
)

// ValidCycle reports whether c is a billing cycle the tracker understands.
func ValidCycle(c string) bool {
	switch c {
	case CycleWeekly, CycleMonthly, CycleYearly:
		return true
	}
	return false
}

// DateOf returns midnight, Thai time, of the Thai calendar day t falls on. Due
// dates are whole days, and MongoDB hands times back in UTC — a bill due on the
// 14th is stored as 17:00 UTC on the 13th — so every comparison goes through here.
func DateOf(t time.Time) time.Time {
	local := t.In(Zone)
	return time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, Zone)
}

// DueDateString formats a due date as the Thai calendar day, "2006-01-02". The
// API sends this alongside the stored instant so clients never have to convert.
func DueDateString(t time.Time) string {
	return t.In(Zone).Format("2006-01-02")
}

// ParseDueDate reads a due date sent by a client. A plain "YYYY-MM-DD" is a Thai
// calendar day; an RFC 3339 timestamp is reduced to the Thai day it falls on.
func ParseDueDate(raw string) (time.Time, error) {
	s := strings.TrimSpace(raw)
	if t, err := time.ParseInLocation("2006-01-02", s, Zone); err == nil {
		return t, nil
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return DateOf(t), nil
	}
	return time.Time{}, errors.New("invalid due date, expected YYYY-MM-DD")
}

// AdvanceDue returns the due date one billing cycle after due.
//
// Monthly and yearly bills land on anchorDay, clamped to the length of the target
// month. time.AddDate would normalise Jan 31 + 1 month to Mar 3 and skip February
// entirely; clamping gives Feb 28, and keeping the anchor separately from the date
// lets the following month return to the 31st instead of drifting to the 28th for
// good. An anchorDay of zero or less falls back to the due date's own day.
func AdvanceDue(due time.Time, cycle string, anchorDay int) (time.Time, error) {
	d := DateOf(due)
	if anchorDay <= 0 {
		anchorDay = d.Day()
	}
	switch cycle {
	case CycleWeekly:
		return d.AddDate(0, 0, 7), nil
	case CycleMonthly:
		return onAnchorDay(d.Year(), d.Month()+1, anchorDay), nil
	case CycleYearly:
		return onAnchorDay(d.Year()+1, d.Month(), anchorDay), nil
	}
	return time.Time{}, fmt.Errorf("unknown billing cycle %q", cycle)
}

// onAnchorDay is anchor day of the given month, or its last day when shorter.
// time.Date normalises month 13 into January of the next year.
func onAnchorDay(year int, month time.Month, anchor int) time.Time {
	first := time.Date(year, month, 1, 0, 0, 0, 0, Zone)
	last := first.AddDate(0, 1, -1).Day()
	if anchor > last {
		anchor = last
	}
	return time.Date(first.Year(), first.Month(), anchor, 0, 0, 0, 0, Zone)
}

// DaysUntil counts Thai calendar days from now until due: 0 when due today,
// negative when overdue. The zone has no daylight saving, so days are exactly 24h.
func DaysUntil(due, now time.Time) int {
	return int(DateOf(due).Sub(DateOf(now)) / (24 * time.Hour))
}

// DueStatus classifies a bill for display from its days until due.
func DueStatus(daysUntil int, active bool) string {
	switch {
	case !active:
		return StatusPaused
	case daysUntil < 0:
		return StatusOverdue
	case daysUntil == 0:
		return StatusDueToday
	case daysUntil <= DueSoonDays:
		return StatusDueSoon
	}
	return StatusUpcoming
}

// DueLabel is the short human label for a due date: Today, Tomorrow, Yesterday,
// or "Oct 14".
func DueLabel(due, now time.Time) string {
	switch DaysUntil(due, now) {
	case 0:
		return "Today"
	case 1:
		return "Tomorrow"
	case -1:
		return "Yesterday"
	}
	return due.In(Zone).Format("Jan 2")
}

// MonthlyEquivalent spreads a bill's amount over a month, rounded to the nearest
// Baht: a weekly bill is charged 52 times a year, a yearly one once. It is how a
// ฿1,990 yearly plan and a ฿419 monthly one add up to one comparable total.
func MonthlyEquivalent(amount int64, cycle string) int64 {
	switch cycle {
	case CycleWeekly:
		return (amount*52 + 6) / 12
	case CycleMonthly:
		return amount
	case CycleYearly:
		return (amount + 6) / 12
	}
	return 0
}
