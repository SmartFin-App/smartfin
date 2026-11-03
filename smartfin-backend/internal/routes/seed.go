package routes

import (
	"time"

	"github.com/SmartFin-App/smartfin-backend/internal/models"
	"go.mongodb.org/mongo-driver/v2/bson"
)

type demoRow struct {
	year     int
	month    time.Month
	day      int
	merchant string
	amount   int64
	category string
}

// demoRows are the Nov 2025–Apr 2026 expenses POST /admin/seed-transactions
// inserts. cmd/eval seeds every eval user with them and its scripted questions
// depend on their shape: Shopping is December's biggest category and January is
// the most expensive month, so keep both true when changing a row.
//
// April carries the spending the AI Coach should flag when asked about bad
// expenses (internal/insights): a run of small Starbucks and Line MAN orders,
// and a concert ticket far above the usual Entertainment spend.
var demoRows = []demoRow{
	// November 2025
	{2025, 11, 3, "Big C Supermarket", 2800, "Groceries"},
	{2025, 11, 5, "Grab Ride", 350, "Transport"},
	{2025, 11, 8, "MK Restaurant", 1200, "Food"},
	{2025, 11, 10, "True Move H", 599, "Bills"},
	{2025, 11, 15, "Central Department Store", 3500, "Shopping"},
	{2025, 11, 18, "Starbucks Coffee", 280, "Food"},
	{2025, 11, 22, "Bumrungrad Hospital", 1500, "Health"},
	{2025, 11, 25, "Line MAN", 450, "Food"},
	// December 2025
	{2025, 12, 2, "Lotus's", 3200, "Groceries"},
	{2025, 12, 5, "Netflix", 419, "Entertainment"},
	{2025, 12, 10, "Siam Paragon", 5800, "Shopping"},
	{2025, 12, 12, "Grab Ride", 420, "Transport"},
	{2025, 12, 15, "Yakiniku Like", 890, "Food"},
	{2025, 12, 20, "Christmas Gift", 2500, "Shopping"},
	{2025, 12, 22, "AIS Mobile", 799, "Bills"},
	// January 2026
	{2026, 1, 3, "Big C Supermarket", 2600, "Groceries"},
	{2026, 1, 6, "Starbucks Coffee", 320, "Food"},
	{2026, 1, 8, "BTS Rabbit Card Top Up", 500, "Transport"},
	{2026, 1, 10, "New Year Clothes", 4200, "Shopping"},
	{2026, 1, 15, "Thai Airways", 8900, "Transport"},
	{2026, 1, 16, "Chiangmai Hotel", 3200, "Shopping"},
	{2026, 1, 20, "True Move H", 599, "Bills"},
	{2026, 1, 25, "Line MAN", 380, "Food"},
	// February 2026
	{2026, 2, 2, "Lotus's", 2900, "Groceries"},
	{2026, 2, 14, "Valentine Dinner", 2200, "Food"},
	{2026, 2, 16, "Grab Ride", 290, "Transport"},
	{2026, 2, 18, "Netflix", 419, "Entertainment"},
	{2026, 2, 20, "Samitivej Hospital", 2800, "Health"},
	{2026, 2, 22, "AIS Mobile", 799, "Bills"},
	// March 2026
	{2026, 3, 3, "Big C Supermarket", 3100, "Groceries"},
	{2026, 3, 5, "Starbucks Coffee", 350, "Food"},
	{2026, 3, 8, "Grab Ride", 410, "Transport"},
	{2026, 3, 12, "Central World", 6500, "Shopping"},
	{2026, 3, 15, "True Move H", 599, "Bills"},
	{2026, 3, 18, "Yakiniku Like", 950, "Food"},
	{2026, 3, 20, "Netflix", 419, "Entertainment"},
	{2026, 3, 25, "Pharmacy", 680, "Health"},
	// April 2026
	{2026, 4, 1, "Lotus's", 2750, "Groceries"},
	{2026, 4, 2, "Starbucks Coffee", 280, "Food"},
	{2026, 4, 3, "Grab Ride", 180, "Transport"},
	{2026, 4, 5, "Songkran Clothes", 3200, "Shopping"},
	{2026, 4, 6, "Line MAN", 420, "Food"},
	{2026, 4, 8, "MK Restaurant", 1100, "Food"},
	{2026, 4, 9, "Starbucks Coffee", 300, "Food"},
	{2026, 4, 10, "Netflix", 419, "Entertainment"},
	{2026, 4, 12, "True Move H", 599, "Bills"},
	{2026, 4, 13, "Line MAN", 380, "Food"},
	{2026, 4, 15, "Starbucks Coffee", 260, "Food"},
	{2026, 4, 18, "Thai Ticket Major", 4500, "Entertainment"},
	{2026, 4, 19, "Line MAN", 450, "Food"},
	{2026, 4, 22, "Starbucks Coffee", 320, "Food"},
	{2026, 4, 26, "Line MAN", 390, "Food"},
	{2026, 4, 28, "Starbucks Coffee", 290, "Food"},
}

// demoTransactions builds the seed documents for one user.
func demoTransactions(userID string, now time.Time) []any {
	out := make([]any, 0, len(demoRows))
	for _, r := range demoRows {
		out = append(out, demoTransaction(userID, r, now))
	}
	return out
}

func demoTransaction(userID string, r demoRow, now time.Time) models.Transaction {
	return models.Transaction{
		ID: bson.NewObjectID(), UserID: userID, Merchant: r.merchant, Amount: r.amount,
		Type: "expense", Category: r.category, Source: "manual",
		Date:      time.Date(r.year, r.month, r.day, 0, 0, 0, 0, time.UTC),
		CreatedAt: now, UpdatedAt: now,
	}
}
