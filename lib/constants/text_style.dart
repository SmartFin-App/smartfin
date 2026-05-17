import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'color_style.dart';

class AppTextStyles {
  /// Used for: App name / big numbers
  static TextStyle appName = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w800,
    fontSize: 60,
    letterSpacing: -3,
    color: AppColors.textDark,
  );

  /// Used for: Large display titles
  static TextStyle displayLarge = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w800,
    fontSize: 36,
    letterSpacing: -1.8,
    color: AppColors.textDark,
  );

  /// Used for: Medium display titles
  static TextStyle displayMedium = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w800,
    fontSize: 30,
    letterSpacing: -0.75,
    color: AppColors.textDark,
  );

  /// Used for: Screen titles
  static TextStyle screenTitle = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w700,
    fontSize: 18,
    letterSpacing: -0.45,
    color: AppColors.textDark,
  );

  /// Used for: User greetings
  static TextStyle greeting = GoogleFonts.bricolageGrotesque(
    fontWeight: FontWeight.w800,
    fontSize: 20,
    letterSpacing: -0.5,
    color: AppColors.textDark,
  );

  /// Used for: Tagline (should be used with .toUpperCase())
  static TextStyle tagline = GoogleFonts.inter(
    fontWeight: FontWeight.w700,
    fontSize: 14,
    letterSpacing: 4.2,
    color: AppColors.textDark,
  );

  /// Used for: Body text
  static TextStyle bodyMedium = GoogleFonts.inter(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    color: AppColors.textDark,
  );

  /// Used for: Bold body text
  static TextStyle bodyBold = GoogleFonts.inter(
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: AppColors.textDark,
  );

  /// Used for: Buttons (should be used with .toUpperCase())
  static TextStyle buttonLabel = GoogleFonts.inter(
    fontWeight: FontWeight.w800,
    fontSize: 12,
    letterSpacing: 2.4,
    color: AppColors.textDark,
  );

  /// Used for: Labels / caps (should be used with .toUpperCase())
  static TextStyle label = GoogleFonts.inter(
    fontWeight: FontWeight.w800,
    fontSize: 10,
    letterSpacing: 2,
    color: AppColors.textDark,
  );

  /// Used for: Captions
  static TextStyle caption = GoogleFonts.inter(
    fontWeight: FontWeight.w500,
    fontSize: 11,
    color: AppColors.textDark,
  );

  /// Used for: Transaction names in lists
  static TextStyle transactionName = GoogleFonts.inter(
    fontWeight: FontWeight.w700,
    fontSize: 12,
    color: AppColors.textDark,
  );

  /// Used for: Transaction metadata (should be used with .toUpperCase())
  static TextStyle transactionMeta = GoogleFonts.inter(
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: -0.25,
    color: AppColors.textDark,
  );
}
