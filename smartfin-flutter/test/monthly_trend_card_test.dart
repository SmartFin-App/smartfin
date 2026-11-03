import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/features/dashboard/presentation/widgets/monthly_trend_card.dart';

/// The server's shape: newest first, six months, empty ones included.
List<Map<String, dynamic>> _history(
  List<int> spentOldestFirst, {
  int budget = 10000,
}) {
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < spentOldestFirst.length; i++) {
    final spent = spentOldestFirst[i];
    rows.add({
      'month': '2026-${(6 + i).toString().padLeft(2, '0')}',
      'total_expenses': spent,
      'budget_limit': budget,
      'budget_percentage': budget > 0 ? spent * 100 / budget : 0,
    });
  }
  return rows.reversed.toList();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('TrendMonth.fromHistory', () {
    test('sorts oldest first', () {
      final months = TrendMonth.fromHistory(
        _history([9000, 8000, 7000, 6000, 5000, 4000]),
      );
      expect(months.map((m) => m.month), [
        '2026-06',
        '2026-07',
        '2026-08',
        '2026-09',
        '2026-10',
        '2026-11',
      ]);
    });

    test('drops the empty months before the first expense', () {
      final months = TrendMonth.fromHistory(_history([0, 0, 0, 3000, 0, 1200]));
      expect(months.map((m) => m.month), ['2026-09', '2026-10', '2026-11']);
    });

    test('is empty when only the current month has spending', () {
      expect(TrendMonth.fromHistory(_history([0, 0, 0, 0, 0, 1200])), isEmpty);
    });

    test('is empty with no spending, or a malformed reply', () {
      expect(TrendMonth.fromHistory(_history([0, 0, 0, 0, 0, 0])), isEmpty);
      expect(TrendMonth.fromHistory(null), isEmpty);
      expect(
        TrendMonth.fromHistory([
          {'month': 'soon'},
          42,
        ]),
        isEmpty,
      );
    });
  });

  testWidgets('trend card lays out, and tapping a bar selects that month', (
    tester,
  ) async {
    String? opened;
    final months = TrendMonth.fromHistory(
      _history([9000, 12500, 8000, 0, 7000, 4200]),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MonthlyTrendCard(
              months: months,
              onOpenMonth: (m) => opened = m,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Last 6 months'), findsOneWidget);
    // Sep had no spending, so it is left out of the average:
    // (9000 + 12500 + 8000 + 7000) / 4.
    expect(find.text('฿9,125 a month on average'), findsOneWidget);
    expect(find.text('Budget ฿10,000'), findsOneWidget);
    // The current month is selected first.
    expect(find.text('November 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tap the July column high up, on the grey track above the bar.
    final chart = tester.getRect(find.byType(BarChart));
    final slot = chart.width / months.length;
    await tester.tapAt(Offset(chart.left + slot * 1.5, chart.top + 10));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.textContaining('125% of budget'), findsOneWidget);

    await tester.tap(find.text('View in History'));
    expect(opened, '2026-07');
  });

  testWidgets('trend card fits a small phone over budget', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MonthlyTrendCard(
              months: TrendMonth.fromHistory(
                _history([12000, 15800, 8000, 9000, 7000, 128450]),
              ),
              onOpenMonth: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('so far'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
