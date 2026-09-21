import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/widgets/action_hub_sheet.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('action hub lays out its three ways to add an expense',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ActionHubSheet(),
        ),
      ),
    ));

    expect(find.text('Add an expense'), findsOneWidget);
    expect(find.text('Scan a slip'), findsOneWidget);
    expect(find.text('Auto-Detect'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // A RenderFlex overflow would have been reported as an exception.
    expect(tester.takeException(), isNull);
  });
}
