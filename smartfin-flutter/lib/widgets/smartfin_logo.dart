import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The SmartFin wordmark: the name itself, set as the logo.
///
/// "Smart" carries the app's ink colour and "Fin" the brand orange, which is
/// what makes plain text read as a mark rather than as a heading. There is no
/// icon beside it on purpose — the header sits above a busy scrolling list, and
/// a badge competed with the cards below it.
class SmartFinLogo extends StatelessWidget {
  final double fontSize;
  final Color textColor;
  final Color accentColor;

  /// Tracking tightens as the wordmark grows — the splash sets it far tighter
  /// than the 24px header, because loose letters at 60px read as a sentence.
  final double letterSpacing;

  const SmartFinLogo({
    super.key,
    this.fontSize = 24,
    this.textColor = const Color(0xFF333333),
    this.accentColor = const Color(0xFFFF9F29),
    this.letterSpacing = -0.5,
  });

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w800,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      color: textColor,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Smart', style: style),
          TextSpan(text: 'Fin', style: style.copyWith(color: accentColor)),
        ],
      ),
      // The wordmark is the product's name, so screen readers should announce it
      // as one word rather than as two coloured fragments.
      semanticsLabel: 'SmartFin',
    );
  }
}
