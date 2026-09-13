package summaries

import (
	"strings"
	"time"
)

// GoalProjection turns a savings goal into a plan. The plan is the user's own:
// monthly income minus the budget they chose is what that budget leaves to set
// aside each month. From it we estimate how long the goal takes and, when a target
// date is set, whether the budget reaches it in time. All figures are whole Baht,
// and nothing here is inferred from spending.
type GoalProjection struct {
	// BudgetSet is false when no budget limit is set — there is no plan to project.
	BudgetSet bool
	// PlannedMonthlySaving is income − budget, floored at zero. It is also zero
	// when the budget uses all of the income.
	PlannedMonthlySaving int64
	// MonthsToGoal is how many months of planned saving cover what remains: 0 once
	// the goal is met, nil when the plan saves nothing.
	MonthsToGoal *int

	// The fields below describe the target date and mean something only when
	// TargetParsed is true. The coach can store free text ("in 6 months"), which
	// is deliberately left unparsed rather than guessed at.
	TargetParsed          bool
	TargetPassed          bool
	MonthsUntilTarget     int
	RequiredMonthlySaving int64
	OnTrack               bool
}

// ProjectGoal builds a GoalProjection for the amount still left to save.
func ProjectGoal(remaining, monthlyIncome, budgetLimit int64, targetDate string, now time.Time) GoalProjection {
	p := GoalProjection{BudgetSet: budgetLimit > 0}
	if p.BudgetSet && monthlyIncome > budgetLimit {
		p.PlannedMonthlySaving = monthlyIncome - budgetLimit
	}

	switch {
	case remaining <= 0:
		zero := 0
		p.MonthsToGoal = &zero
	case p.PlannedMonthlySaving > 0:
		months := int(ceilDiv(remaining, p.PlannedMonthlySaving))
		p.MonthsToGoal = &months
	}

	target, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(targetDate), Zone)
	if err != nil {
		return p
	}
	p.TargetParsed = true

	if remaining <= 0 {
		p.OnTrack = true
		return p
	}

	local := now.In(Zone)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, Zone)
	if target.Before(today) {
		p.TargetPassed = true
		p.RequiredMonthlySaving = remaining
		return p
	}

	// Savings are banked as each month completes, so count the month boundaries
	// between now and the target. A target later this month still leaves one
	// month to find the money in.
	months := (target.Year()-local.Year())*12 + int(target.Month()) - int(local.Month())
	if months < 1 {
		months = 1
	}
	p.MonthsUntilTarget = months
	p.RequiredMonthlySaving = ceilDiv(remaining, int64(months))
	p.OnTrack = p.PlannedMonthlySaving > 0 && p.PlannedMonthlySaving >= p.RequiredMonthlySaving
	return p
}

// ceilDiv divides rounding up, so a plan never promises a goal a month early.
func ceilDiv(a, b int64) int64 {
	if b <= 0 {
		return 0
	}
	return (a + b - 1) / b
}
