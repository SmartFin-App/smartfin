import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
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
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
