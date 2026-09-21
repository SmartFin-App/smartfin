import 'package:flutter/material.dart';

class AppColors {
  // ── Surfaces ──────────────────────────────────────────────────────────────

  // App background
  static const Color cream = Color(0xFFFFF9F0);

  // Cards, input fields, sheets
  static const Color white = Color(0xFFFFFFFF);

  // Skeletons, progress tracks, the donut's unspent budget
  static const Color surfaceMuted = Color(0xFFF3ECE1);

  // Card borders, input borders, dividers
  static const Color border = Color(0xFFEAE2D6);

  // ── Brand ─────────────────────────────────────────────────────────────────

  // Buttons, active states, accents, progress bar
  static const Color primary = Color(0xFFFF9F29);

  // Orange for small text and links. The brand orange is too light to read
  // as text on white (about 2:1); this one clears 4.5:1.
  static const Color primaryText = Color(0xFFB45F06);

  // Text and icons on an orange fill. White on the brand orange is about 2:1,
  // well under the 4.5:1 text needs; the ink is about 8:1.
  static const Color onPrimary = textDark;

  // Selected button background (rgba(255, 159, 41, 0.05))
  static const Color primarySoft = Color(0x0DFF9F29);

  // Button shadow/glow (rgba(255, 159, 41, 0.2))
  static const Color primaryGlow = Color(0x33FF9F29);

  // ── Text ──────────────────────────────────────────────────────────────────

  // Headings, body text, input text
  static const Color textDark = Color(0xFF2A2622);

  // Subtitles, captions, metadata. Warm grey that still reads on white.
  static const Color textSecondary = Color(0xFF786F66);

  // Placeholders, disabled text, inactive nav. Too faint for anything the user
  // has to read.
  static const Color textMuted = Color(0xFF9E9E9E);

  // ── Status ────────────────────────────────────────────────────────────────

  // Over budget, overdue, destructive actions
  static const Color danger = Color(0xFFDC2626);

  // Budget left, confirmations
  static const Color success = Color(0xFF16A34A);

  // Income amounts on rows recorded before SmartFin became spending-only
  static const Color income = Color(0xFF4CAF50);

  // Card shadow (rgba(0, 0, 0, 0.1))
  static const Color cardShadow = Color(0x1A000000);
}

/// Corner radii. Every rounded shape in the app should use one of these.
class AppRadius {
  static const double sm = 10; // chips, small tiles
  static const double md = 14; // buttons, inputs, icon tiles
  static const double lg = 20; // cards
  static const double xl = 28; // sheets, the nav bar
  static const double pill = 999;
}

/// Spacing steps, on a 4px grid.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Side inset of every screen's content.
  static const double screen = 20;
}

class AppShadows {
  /// A soft, warm lift for cards: wide and faint rather than dark and tight.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F2A2622), blurRadius: 24, offset: Offset(0, 8)),
  ];
}
