package models

import "testing"

func TestValidateSplit(t *testing.T) {
	cases := []struct {
		name    string
		amount  int64
		total   int64
		people  int
		wantErr bool
	}{
		{"not split", 300, 0, 0, false},
		{"even split", 300, 900, 3, false},
		{"uneven share", 500, 900, 3, false},
		{"share equal to the slip", 900, 900, 2, false},
		{"total without people", 300, 900, 0, true},
		{"people without total", 300, 0, 3, true},
		{"split with nobody else", 900, 900, 1, true},
		{"share above the slip", 1000, 900, 3, true},
		{"negative total", 300, -900, 3, true},
		{"negative people", 300, 900, -3, true},
		{"too many people", 1, 900, MaxSplitPeople + 1, true},
	}
	for _, tc := range cases {
		err := ValidateSplit(tc.amount, tc.total, tc.people)
		if (err != nil) != tc.wantErr {
			t.Errorf("%s: ValidateSplit(%d, %d, %d) error = %v, wantErr %v",
				tc.name, tc.amount, tc.total, tc.people, err, tc.wantErr)
		}
	}
}

func TestNormalizeCategory(t *testing.T) {
	cases := map[string]string{
		"Food":          "Food",
		"groceries":     "Groceries",
		" TRANSPORT ":   "Transport",
		"Entertainment": "Entertainment",
		"Healthcare":    "Other",
		"Gifts":         "Other",
		"":              "Other",
	}
	for raw, want := range cases {
		if got := NormalizeCategory(raw); got != want {
			t.Errorf("NormalizeCategory(%q) = %q, want %q", raw, got, want)
		}
	}
}
