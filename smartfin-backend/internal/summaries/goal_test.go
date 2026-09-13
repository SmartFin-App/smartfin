package summaries

import (
	"testing"
	"time"
)

// 13 September 2026, mid-afternoon in Bangkok.
var projNow = time.Date(2026, 9, 13, 15, 0, 0, 0, Zone)

func TestProjectGoalWithoutBudgetHasNoPlan(t *testing.T) {
	p := ProjectGoal(5000, 12000, 0, "", projNow)
	if p.BudgetSet || p.PlannedMonthlySaving != 0 || p.MonthsToGoal != nil {
		t.Fatalf("no budget should mean no plan, got %+v", p)
	}
}

func TestProjectGoalBudgetUsingAllIncomeSavesNothing(t *testing.T) {
	for _, budget := range []int64{12000, 15000} {
		p := ProjectGoal(5000, 12000, budget, "", projNow)
		if !p.BudgetSet || p.PlannedMonthlySaving != 0 || p.MonthsToGoal != nil {
			t.Errorf("budget %d on 12000 income should plan zero saving, got %+v", budget, p)
		}
	}
}

// The reported case: ฿12,000 income, a 70% budget, and a ฿5,000 goal.
func TestProjectGoalPlannedSavingAndMonthsToGoal(t *testing.T) {
	p := ProjectGoal(5000, 12000, 8400, "", projNow)
	if p.PlannedMonthlySaving != 3600 {
		t.Errorf("planned = %d, want 3600", p.PlannedMonthlySaving)
	}
	if p.MonthsToGoal == nil || *p.MonthsToGoal != 2 {
		t.Errorf("months to goal = %v, want 2 (5000 / 3600 rounded up)", p.MonthsToGoal)
	}
	if p.TargetParsed {
		t.Error("no target date should leave the target fields unset")
	}
}

func TestProjectGoalMetNeedsNoMonths(t *testing.T) {
	p := ProjectGoal(0, 12000, 8400, "2026-12-31", projNow)
	if p.MonthsToGoal == nil || *p.MonthsToGoal != 0 || !p.OnTrack {
		t.Errorf("a met goal should need 0 months and be on track, got %+v", p)
	}
}

func TestProjectGoalFreeTextTargetIsNotGuessed(t *testing.T) {
	p := ProjectGoal(5000, 12000, 8400, "in 6 months", projNow)
	if p.TargetParsed || p.OnTrack || p.RequiredMonthlySaving != 0 {
		t.Errorf("a free-text target must not be interpreted, got %+v", p)
	}
}

// September to December leaves 3 month boundaries: 5000 / 3 = 1667 needed.
func TestProjectGoalReachableTarget(t *testing.T) {
	p := ProjectGoal(5000, 12000, 8400, "2026-12-31", projNow)
	if p.MonthsUntilTarget != 3 || p.RequiredMonthlySaving != 1667 || !p.OnTrack {
		t.Errorf("want 3 months, 1667/month, on track; got %+v", p)
	}
}

func TestProjectGoalTargetTooSoon(t *testing.T) {
	p := ProjectGoal(12000, 12000, 8400, "2026-10-31", projNow)
	if p.MonthsUntilTarget != 1 || p.RequiredMonthlySaving != 12000 || p.OnTrack {
		t.Errorf("want 1 month, 12000/month, not on track; got %+v", p)
	}
}

func TestProjectGoalTargetLaterThisMonthStillGetsOneMonth(t *testing.T) {
	p := ProjectGoal(3000, 12000, 8400, "2026-09-30", projNow)
	if p.MonthsUntilTarget != 1 || p.RequiredMonthlySaving != 3000 || !p.OnTrack {
		t.Errorf("want 1 month, 3000 needed, on track with 3600 planned; got %+v", p)
	}
}

func TestProjectGoalPassedTarget(t *testing.T) {
	p := ProjectGoal(5000, 12000, 8400, "2026-08-01", projNow)
	if !p.TargetPassed || p.OnTrack || p.RequiredMonthlySaving != 5000 {
		t.Errorf("a past target should be passed and not on track, got %+v", p)
	}
}
