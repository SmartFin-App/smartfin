package main

import "testing"

func TestMerchantMatches(t *testing.T) {
	cases := []struct {
		got     string
		aliases []string
		want    bool
	}{
		{"CP AXTRA PUBLIC COMPANY LIMITED (HEAD", []string{"cp axtra", "lotus"}, true},
		{"Lotus's", []string{"cp axtra", "lotus"}, true},
		{"I Wanna Eat Yogurt", []string{"i wanna eat yogurt"}, true},
		{"บริษัท ดิไวน์ คอนเน็ค จำกัด", []string{"divine connect", "ดิไวน์"}, true},
		{"Divine Connect Co., Ltd.", []string{"divine connect", "ดิไวน์"}, true},
		{"Unknown Merchant", []string{"watson"}, false},
		{"", []string{"mixue"}, false},
	}
	for _, c := range cases {
		if got := merchantMatches(c.got, c.aliases); got != c.want {
			t.Errorf("merchantMatches(%q, %v) = %v, want %v", c.got, c.aliases, got, c.want)
		}
	}
}

func TestAmountMatches(t *testing.T) {
	for _, c := range []struct {
		got   int64
		label float64
		want  bool
	}{
		{702, 702.50, true}, {703, 702.50, true}, {701, 702.50, false},
		{1152, 1152.39, true}, {115, 115, true}, {120, 115, false},
	} {
		if got := amountMatches(c.got, c.label); got != c.want {
			t.Errorf("amountMatches(%d, %v) = %v, want %v", c.got, c.label, got, c.want)
		}
	}
}

func TestScoreTrial(t *testing.T) {
	l := Label{File: "x", Aliases: []string{"watson"}, Amount: 288, Date: ""}
	s := scoreTrial(&Trial{Status: "ok", Merchant: "Watsons The Street", Amount: 288, Date: "2026-09-13"}, l, "2026-09-13")
	if !s.AllOK {
		t.Errorf("no printed date and today's date returned, as the prompt asks, is right: %+v", s)
	}
	s = scoreTrial(&Trial{Status: "ok", Merchant: "Watsons", Amount: 288, Date: "2024-05-16"}, l, "2026-09-13")
	if s.AllOK || !s.DateInvented {
		t.Errorf("an invented date on a receipt with no printed date must fail and be flagged: %+v", s)
	}

	l.Date = "2026-09-07"
	s = scoreTrial(&Trial{Status: "ok", Merchant: "Watsons", Amount: 288, Date: "2026-09-13"}, l, "2026-09-13")
	if s.AllOK || !s.DateDefaulted {
		t.Errorf("a printed date read as today must fail and be flagged: %+v", s)
	}

	s = scoreTrial(&Trial{Status: "ok", Merchant: "Unknown Merchant", Amount: 0, Date: "2026-09-07"}, l, "2026-09-13")
	if s.AllOK || !s.Fallback {
		t.Errorf("the scanner fallback must fail and be flagged: %+v", s)
	}

	if s := scoreTrial(&Trial{Status: "error"}, l, "2026-09-13"); s.AllOK {
		t.Error("an error is never right")
	}
}

func TestNormalizeKeepsThaiMarks(t *testing.T) {
	if normalize("ป้าอ้วน ตามสั่ง!") != "ป้าอ้วนตามสั่ง" {
		t.Errorf("got %q", normalize("ป้าอ้วน ตามสั่ง!"))
	}
}
