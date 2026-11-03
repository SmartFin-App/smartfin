package handlers

import "testing"

func TestNotASlip(t *testing.T) {
	cases := []struct {
		name   string
		result map[string]interface{}
		want   bool
	}{
		{"model says not a slip", map[string]interface{}{"is_slip": false}, true},
		{"model says slip", map[string]interface{}{"is_slip": true, "total_amount": 350.0}, false},
		{"field missing", map[string]interface{}{"merchant_name": "KFC"}, false},
		{"field not a bool", map[string]interface{}{"is_slip": "false"}, false},
	}
	for _, c := range cases {
		if got := notASlip(c.result); got != c.want {
			t.Errorf("%s: notASlip = %v, want %v", c.name, got, c.want)
		}
	}
}
