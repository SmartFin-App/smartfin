// Package summaries holds the month-window rules and cache invalidation shared by
// the HTTP handlers and the coach agents. Both used to compute month boundaries
// themselves, in different timezones, and disagreed about which month a
// transaction belonged to.
package summaries

import (
	"context"
	"fmt"
	"log"
	"regexp"
	"strconv"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
)

// Zone is the fixed +07:00 offset Thailand observes year-round (no DST).
// Month windows are anchored to it so a Baht-denominated "day" matches the user's
// calendar rather than the server's — a UTC server would otherwise file a 06:00
// Bangkok expense on the 1st under the previous month.
var Zone = time.FixedZone("ICT", 7*60*60)

var monthPattern = regexp.MustCompile(`^\d{4}-\d{2}$`)

// Bounds parses "2026-04" into its half-open [start, end) window in Thai local time.
func Bounds(month string) (time.Time, time.Time, error) {
	if !monthPattern.MatchString(month) {
		return time.Time{}, time.Time{}, fmt.Errorf("invalid month format: %q (want YYYY-MM)", month)
	}
	year, _ := strconv.Atoi(month[:4])
	monthNum, _ := strconv.Atoi(month[5:])
	if monthNum < 1 || monthNum > 12 {
		return time.Time{}, time.Time{}, fmt.Errorf("invalid month number: %q", month)
	}
	start := time.Date(year, time.Month(monthNum), 1, 0, 0, 0, 0, Zone)
	return start, start.AddDate(0, 1, 0), nil
}

// StringOf renders a time as the "YYYY-MM" key used throughout, in Thai local time.
func StringOf(t time.Time) string {
	return t.In(Zone).Format("2006-01")
}

// Invalidate drops the cached summary for a user's month so the next read recomputes it.
//
// It deliberately does not spare frozen months: a past month that gains, loses, or
// changes a transaction is stale by definition, and skipping it left backdated
// entries permanently invisible to every total while still showing in the list.
func Invalidate(ctx context.Context, col *mongo.Collection, userID, month string) {
	if col == nil || userID == "" || month == "" {
		return
	}
	if _, err := col.DeleteOne(ctx, bson.M{"user_id": userID, "month": month}); err != nil {
		log.Printf("Warning: could not invalidate summary for %s/%s: %v", userID, month, err)
	}
}

// InvalidateFor invalidates every month touched by a change, de-duplicated — an edit
// that moves a transaction across a month boundary makes both months stale.
func InvalidateFor(ctx context.Context, col *mongo.Collection, userID string, dates ...time.Time) {
	seen := make(map[string]bool, len(dates))
	for _, d := range dates {
		if d.IsZero() {
			continue
		}
		if m := StringOf(d); !seen[m] {
			seen[m] = true
			Invalidate(ctx, col, userID, m)
		}
	}
}

// Baht formats a whole-baht amount for display, e.g. 15000 → "฿15,000". Clients
// render these strings as-is rather than formatting money themselves.
func Baht(amount int64) string {
	s := strconv.FormatInt(amount, 10)
	neg := amount < 0
	if neg {
		s = s[1:]
	}
	var b []byte
	for i := range len(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			b = append(b, ',')
		}
		b = append(b, s[i])
	}
	if neg {
		return "-฿" + string(b)
	}
	return "฿" + string(b)
}
