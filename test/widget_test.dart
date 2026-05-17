// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:smart_fin/main.dart';

void main() {
  testWidgets('SmartFin dashboard smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartFinApp());

    // Verify that our app bar title is 'SmartFin'.
    expect(find.text('SmartFin'), findsOneWidget);
    
    // Verify that 'Welcome back' text is present.
    expect(find.textContaining('Welcome back'), findsOneWidget);
  });
}
