package main

import (
	"encoding/csv"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"unicode"
)

// Label is the hand-checked truth for one image.
type Label struct {
	File        string
	Kind        string // eslip | receipt
	Source      string
	Aliases     []string
	Amount      float64
	Date        string // YYYY-MM-DD, or "" when the image shows no date
	Orientation string // upright | rotated | upside_down | tilted
	Notes       string
	Verified    bool
}

func loadLabels(path string) ([]Label, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	rows, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, fmt.Errorf("%s has no label rows", path)
	}
	col := map[string]int{}
	for i, h := range rows[0] {
		col[strings.TrimSpace(strings.ToLower(h))] = i
	}
	for _, need := range []string{"file", "kind", "merchant", "amount", "date"} {
		if _, ok := col[need]; !ok {
			return nil, fmt.Errorf("%s is missing the %q column", path, need)
		}
	}
	get := func(row []string, name string) string {
		if i, ok := col[name]; ok && i < len(row) {
			return strings.TrimSpace(row[i])
		}
		return ""
	}
	var labels []Label
	for n, row := range rows[1:] {
		if get(row, "file") == "" {
			continue
		}
		amount, err := strconv.ParseFloat(strings.ReplaceAll(get(row, "amount"), ",", ""), 64)
		if err != nil {
			return nil, fmt.Errorf("row %d (%s): bad amount %q", n+2, get(row, "file"), get(row, "amount"))
		}
		var aliases []string
		for _, a := range strings.Split(get(row, "merchant"), "|") {
			if a = strings.TrimSpace(a); a != "" {
				aliases = append(aliases, a)
			}
		}
		if len(aliases) == 0 {
			return nil, fmt.Errorf("row %d (%s): no merchant name", n+2, get(row, "file"))
		}
		v := strings.ToLower(get(row, "verified"))
		labels = append(labels, Label{
			File: get(row, "file"), Kind: get(row, "kind"), Source: get(row, "source"),
			Aliases: aliases, Amount: amount, Date: get(row, "date"),
			Orientation: get(row, "orientation"), Notes: get(row, "notes"),
			Verified: v == "yes" || v == "y" || v == "true" || v == "1",
		})
	}
	return labels, nil
}

// normalize keeps letters, digits and Thai combining marks, lower-cased, so
// "CP AXTRA PUBLIC COMPANY LIMITED (HEAD" and "CP Axtra" compare on content.
func normalize(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || unicode.IsMark(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// merchantMatches: the extracted name contains any accepted alias. Names are
// transliterated from Thai, so exact matching would fail correct answers.
func merchantMatches(got string, aliases []string) bool {
	g := normalize(got)
	if g == "" {
		return false
	}
	for _, a := range aliases {
		if n := normalize(a); n != "" && strings.Contains(g, n) {
			return true
		}
	}
	return false
}

// amountMatches: the scanner returns whole baht, so ฿702.50 is right as 702 or 703.
func amountMatches(got int64, label float64) bool {
	return math.Abs(float64(got)-label) <= 0.5+1e-9
}

// Score is the verdict on one scan.
type Score struct {
	AmountOK      bool  `json:"amount_ok"`
	MerchantOK    bool  `json:"merchant_ok"`
	DateOK        *bool `json:"date_ok,omitempty"`
	AllOK         bool  `json:"all_ok"`
	Fallback      bool  `json:"fallback,omitempty"`
	DateDefaulted bool  `json:"date_defaulted,omitempty"` // returned the run day instead of the printed date
	DateInvented  bool  `json:"date_invented,omitempty"`  // no date printed, and it returned something other than today
}

func scoreTrial(t *Trial, l Label, runDay string) Score {
	var s Score
	if t.Status != "ok" {
		return s
	}
	s.AmountOK = amountMatches(t.Amount, l.Amount)
	s.MerchantOK = merchantMatches(t.Merchant, l.Aliases)
	if l.Date != "" {
		ok := t.Date == l.Date
		s.DateOK = &ok
		s.DateDefaulted = !ok && t.Date == runDay
	} else {
		// No date printed. The scanner prompt says to use today's date then, so any
		// other date was invented — and would file the expense in the wrong month.
		ok := t.Date == runDay
		s.DateOK = &ok
		s.DateInvented = !ok
	}
	s.Fallback = t.Merchant == "Unknown Merchant" || t.Amount == 0
	s.AllOK = s.AmountOK && s.MerchantOK && (s.DateOK == nil || *s.DateOK)
	return s
}
