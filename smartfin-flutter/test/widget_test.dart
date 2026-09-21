import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/features/auth/presentation/login_screen.dart';

// Smoke test on the login screen rather than the whole app: SmartFinApp starts
// at the splash screen, which needs Firebase initialised and then the backend,
// and neither exists in a widget test. The login screen only touches Firebase
// when a button is pressed.
void main() {
  setUpAll(() {
    // Tests have no network, so fonts fall back to the default instead of
    // failing to download.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('login screen renders its form', (WidgetTester tester) async {
    // The screen reads GoRouter from context for its links, so host it in one.
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const LoginScreen())],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
