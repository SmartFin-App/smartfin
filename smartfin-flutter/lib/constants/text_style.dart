import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'color_style.dart';

/// The type scale. Bricolage Grotesque for display figures and titles, Inter
/// for everything read at length. Labels are sentence case: the old 9–10px
/// letter-spaced capitals were hard to read and are being retired.
class AppTextStyles {
  /// Headline figures: the month's spending, a transaction's amount.
  static TextStyle display = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w700,
    fontSize: 32,
    letterSpacing: -1,
    height: 1.1,
    color: AppColors.textDark,
  );

  /// Screen titles.
  static TextStyle title = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w700,
    fontSize: 24,
    letterSpacing: -0.5,
    color: AppColors.textDark,
  );

  /// Card and section headings.
  static TextStyle heading = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w700,
    fontSize: 18,
    letterSpacing: -0.2,
    color: AppColors.textDark,
  );

  /// Body text.
  static TextStyle body = GoogleFonts.inter(
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.45,
    color: AppColors.textDark,
  );

  /// List-row titles, emphasised body text.
  static TextStyle bodyStrong = GoogleFonts.inter(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: AppColors.textDark,
  );

  /// Secondary lines under a title, metadata.
  static TextStyle caption = GoogleFonts.inter(
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  /// Small labels: chips, badges, the "See all" link.
  static TextStyle label = GoogleFonts.inter(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: AppColors.textDark,
  );

  /// Button text.
  static TextStyle button = GoogleFonts.inter(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: 0.1,
  );

  /// Money in lists. Tabular figures keep the digits of a column aligned.
  static TextStyle amount = GoogleFonts.inter(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: AppColors.textDark,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
