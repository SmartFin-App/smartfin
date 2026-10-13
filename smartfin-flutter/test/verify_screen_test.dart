import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/features/scanner/presentation/verify_screen.dart';

Finder _field(String text) => find.widgetWithText(TextFormField, text);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('an even share is rounded to the nearest whole baht', () {
    expect(evenShare(900, 3), 300);
    expect(evenShare(1000, 3), 333);
    expect(evenShare(200, 3), 67);
    expect(evenShare(1, 2), 1);
    expect(evenShare(0, 3), 0);
    expect(evenShare(900, 0), 0);
  });

  testWidgets('a possible duplicate is shown with both ways out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    DuplicateChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showPossibleDuplicateDialog(context, [
                {
                  'merchant': 'Netflix Premium Family Plan Thailand Monthly',
                  'formatted_amount': '-฿419',
                  'formatted_date': 'Today',
                  'source': 'subscription',
                },
              ]);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Already added?'), findsOneWidget);
    expect(find.text('-฿419 · Today · Bill marked paid'), findsOneWidget);
    expect(find.text('Save anyway'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Skip this slip'));
    await tester.pumpAndSettle();
    expect(choice, DuplicateChoice.skip);
  });

  testWidgets('splitting a slip fills in and follows the even share', (
    tester,
  ) async {
    // A phone-sized surface: on the default 800x600 the pinned save bar
    // covers the rows being tapped.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const VerifyScreen(
          extractedData: {'merchant': 'MK Restaurants', 'amount': 900},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Off by default: the slip is saved whole.
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Your share'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Slip total'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    expect(_field('450'), findsOneWidget);

    await tester.tap(find.byTooltip('More people'));
    await tester.pumpAndSettle();
    expect(_field('300'), findsOneWidget);

    // A corrected total moves the share with it.
    await tester.enterText(_field('900'), '1000');
    await tester.pumpAndSettle();
    expect(_field('333'), findsOneWidget);

    // Two is the floor: one person is not a split.
    await tester.tap(find.byTooltip('Fewer people'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fewer people'));
    await tester.pumpAndSettle();
    expect(_field('500'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
