import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryNavy = Color(0xFF0F2594);
  static const Color accentGold = Color(0xFFFFB800);
  static const Color backgroundDark = Color(0xFF0A0E21);
  static const Color cardDark = Color(0xFF1D1E33);
  static const Color textLight = Colors.white;
  static const Color textGray = Color(0xFF8D8E98);

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      primaryColor: primaryNavy,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryNavy,
        secondary: accentGold,
        surface: cardDark,
      ),
      textTheme: GoogleFonts.outfitTextTheme().copyWith(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textLight,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textLight,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 16,
          color: textGray,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textLight,
        ),
      ),
    );
  }
}
