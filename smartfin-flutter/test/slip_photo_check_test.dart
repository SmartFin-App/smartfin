import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:smart_fin/constants/app_theme.dart';
import 'package:smart_fin/features/scanner/presentation/processing_screen.dart';
import 'package:smart_fin/features/scanner/services/slip_photo_check.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('looksLikeSlip passes text with an amount', () {
    // Roughly what ML Kit's Latin model returns for each: Thai script comes
    // through as noise, digits and English labels come through intact.
    const slips = {
      'K PLUS transfer': 'Ins 1n Transfer successful\n'
          '3 Nov 69 14:32\nMr. Somchai\nxxx-x-x1234-x\n1,250.00 UIM\nFee 0.00',
      'SCB EASY with no decimals in OCR': 'SCB\nTransfer\nRef 2026110312345\n350',
      'PromptPay to a shop': 'PromptPay\nKFC Central World\n189.00',
      'retail receipt': "Lotus's\nMILK 2 x 45\n90.00\nTOTAL 350.00\nCASH 500.00",
      'baht sign without satang': 'Coffee ฿65',
      'THB amount': 'Amount THB 1200',
      'tax invoice': 'TAX INVOICE (ABB)\nVAT included\nTotal 120',
    };
    slips.forEach((name, text) {
      test(name, () => expect(SlipPhotoCheck.looksLikeSlip(text), isTrue));
    });
  });

  group('looksLikeSlip turns away text with no amount', () {
    const notSlips = {
      'no text at all (a selfie, a meal)': '',
      'a street sign': 'Sukhumvit Soi 11\nBTS Nana',
      'a dotted date': 'Meeting 12.05.2026',
      'a version number': 'Version 1.2.10',
      'a clock and a battery': '9:41\n85%',
      'a slip word without a figure': 'Total war',
      'a phone number': 'Call 081 234 5678',
    };
    notSlips.forEach((name, text) {
      test(name, () => expect(SlipPhotoCheck.looksLikeSlip(text), isFalse));
    });
  });

  testWidgets('not-a-slip dialog lays out and reports the choice', (
    tester,
  ) async {
    NotASlipChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => choice = await showNotASlipDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text("This doesn't look like a slip"), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();
    expect(choice, NotASlipChoice.enterManually);
  });
}
