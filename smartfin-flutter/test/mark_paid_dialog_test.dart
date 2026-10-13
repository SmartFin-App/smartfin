import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/features/subscriptions/presentation/subscriptions_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<PayChoice?> open(
    WidgetTester tester,
    List<Map<String, dynamic>> matches,
    String tapLabel,
  ) async {
    // A narrow phone, where three dialog actions have to stack.
    tester.view.physicalSize = const Size(960, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    PayChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showDialog<PayChoice>(
                context: context,
                builder: (_) => MarkPaidDialog(
                  name: 'Netflix',
                  formattedAmount: '฿419',
                  category: 'Entertainment',
                  nextDueLabel: '14 Nov 2026',
                  matches: matches,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('with nothing recorded, mark paid logs the expense', (
    tester,
  ) async {
    final choice = await open(tester, const [], 'Mark paid');
    expect(choice, PayChoice.logExpense);
  });

  testWidgets('with the payment already recorded, it offers the date only', (
    tester,
  ) async {
    final matches = [
      {
        'merchant': 'Netflix International Subscription Services Thailand',
        'formatted_amount': '-฿419',
        'formatted_date': 'Yesterday',
      },
    ];
    expect(await open(tester, matches, 'Move date only'), PayChoice.dateOnly);
    expect(await open(tester, matches, 'Log it too'), PayChoice.logExpense);
  });
}
