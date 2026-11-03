import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';

/// One month's bar, read from `GET /api/summary/:user_id/history`.
class TrendMonth {
  final String month; // "2026-08"
  final int spent;
  final int budget;
  final double budgetPercentage;

  const TrendMonth({
    required this.month,
    required this.spent,
    required this.budget,
    required this.budgetPercentage,
  });

  /// A calendar month, so there is no time zone to get wrong.
  DateTime get date {
    final parts = month.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  bool get overBudget => budget > 0 && spent > budget;

  /// The months to chart, oldest first, or an empty list when there is nothing
  /// to compare.
  ///
  /// The server always sends six months, creating empty ones as needed, so a
  /// new user would get five ฿0 bars before their first expense. Those leading
  /// empty months are dropped. The card is hidden unless at least one earlier
  /// month had spending, because the budget card already covers the current one.
  static List<TrendMonth> fromHistory(Object? raw) {
    final months = <TrendMonth>[];
    for (final item in raw is List ? raw : const []) {
      if (item is! Map) continue;
      final month = item['month'];
      if (month is! String || !RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
        continue;
      }
      months.add(
        TrendMonth(
          month: month,
          spent: (item['total_expenses'] as num?)?.toInt() ?? 0,
          budget: (item['budget_limit'] as num?)?.toInt() ?? 0,
          budgetPercentage:
              (item['budget_percentage'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    months.sort((a, b) => a.month.compareTo(b.month));
    final first = months.indexWhere((m) => m.spent > 0);
    if (first < 0) return const [];
    final trimmed = months.sublist(first);
    return trimmed.length < 2 ? const [] : trimmed;
  }
}

String _baht(num amount) =>
    '฿${amount.round().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

/// Spending per month as bars, with the current budget as a dashed line.
/// Tapping a bar shows that month's figures and a link to it in History.
class MonthlyTrendCard extends StatefulWidget {
  /// Oldest first, as [TrendMonth.fromHistory] returns them. The last one is
  /// the current month.
  final List<TrendMonth> months;
  final ValueChanged<String> onOpenMonth;

  const MonthlyTrendCard({
    super.key,
    required this.months,
    required this.onOpenMonth,
  });

  @override
  State<MonthlyTrendCard> createState() => _MonthlyTrendCardState();
}

class _MonthlyTrendCardState extends State<MonthlyTrendCard> {
  late int _selected = widget.months.length - 1;

  @override
  void didUpdateWidget(MonthlyTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refresh can change how many months there are.
    if (_selected >= widget.months.length) {
      _selected = widget.months.length - 1;
    }
  }

  /// The budget in force now; earlier months may have had a different one.
  int get _budget => widget.months.last.budget;

  /// Average over earlier months that had spending. The current month is
  /// left out because it is not over yet, and empty months because a gap
  /// (demo data, then a break) is not a month of spending ฿0.
  int? get _average {
    final past = widget.months
        .take(widget.months.length - 1)
        .where((m) => m.spent > 0)
        .toList();
    if (past.isEmpty) return null;
    return past.fold<int>(0, (sum, m) => sum + m.spent) ~/ past.length;
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.months;
    final average = _average;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last ${months.length} months', style: AppTextStyles.heading),
          if (average != null)
            Text(
              '${_baht(average)} a month on average',
              style: AppTextStyles.caption,
            ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label:
                'Spending by month: ${months.map((m) => '${DateFormat('MMMM').format(m.date)} ${_baht(m.spent)}').join(', ')}',
            child: SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _buildChart(constraints.maxWidth),
              ),
            ),
          ),
          if (_budget > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const _DashSwatch(),
                const SizedBox(width: AppSpacing.sm),
                Text('Budget ${_baht(_budget)}', style: AppTextStyles.caption),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          _buildSelectedMonth(),
        ],
      ),
    );
  }

  Widget _buildChart(double chartWidth) {
    final months = widget.months;
    // Bars fill about half their slot, so two or three months don't look like
    // thin sticks in empty space, and six still fit a small phone.
    final barWidth = (chartWidth / months.length * 0.45).clamp(22.0, 44.0);
    final top = months.fold<int>(
      _budget,
      (max, m) => m.spent > max ? m.spent : max,
    );
    // Headroom so the tallest bar and the budget line never touch the top.
    final maxY = top * 1.15;

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          handleBuiltInTouches: false,
          // The grey track counts, so a short bar is as easy to tap as a tall one.
          allowTouchBarBackDraw: true,
          // Not for touches: a month with no spending is labelled ฿0 inside
          // its empty track, so it reads as ฿0 rather than missing data.
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 6,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  _baht(0),
                  AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
          ),
          touchCallback: (event, response) {
            final index = response?.spot?.touchedBarGroupIndex;
            if (event is FlTapUpEvent && index != null) {
              setState(() => _selected = index);
            }
          },
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (_budget > 0)
              HorizontalLine(
                y: _budget.toDouble(),
                color: AppColors.textSecondary,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
          ],
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox();
                final selected = i == _selected;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    DateFormat('MMM').format(months[i].date),
                    style: AppTextStyles.caption.copyWith(
                      color: selected
                          ? AppColors.textDark
                          : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(
              x: i,
              showingTooltipIndicators: months[i].spent == 0 ? [0] : [],
              barRods: [
                BarChartRodData(
                  toY: months[i].spent.toDouble(),
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  color:
                      (months[i].overBudget
                              ? AppColors.danger
                              : AppColors.primary)
                          .withValues(alpha: i == _selected ? 1 : 0.5),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: AppColors.surfaceMuted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedMonth() {
    final m = widget.months[_selected];
    final isCurrent = _selected == widget.months.length - 1;
    final pct = m.budget > 0 ? m.budgetPercentage.round() : null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(m.date),
                style: AppTextStyles.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _baht(m.spent),
                      style: AppTextStyles.bodyStrong,
                    ),
                    if (isCurrent) const TextSpan(text: ' so far'),
                    if (pct != null)
                      TextSpan(
                        text: ' · $pct% of budget',
                        style: TextStyle(
                          color: m.overBudget ? AppColors.danger : null,
                        ),
                      ),
                  ],
                ),
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => widget.onOpenMonth(m.month),
          child: const Text('View in History'),
        ),
      ],
    );
  }
}

/// The legend's sample of the dashed budget line.
class _DashSwatch extends StatelessWidget {
  const _DashSwatch();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 4,
            height: 1.5,
            margin: const EdgeInsets.only(right: 2),
            color: AppColors.textSecondary,
          ),
      ],
    );
  }
}
