import 'package:flutter/material.dart';

/// xpass design tokens.
///
/// One source of truth for the stealth HUD palette: deep near-black surfaces,
/// hairline white borders, royal-blue accent, and three status hues that read
/// instantly at a glance without pulling the eye off the interview.
abstract final class XpColors {
  // ---------------------------------------------------------------- surfaces
  /// Solid deep background.
  static const Color background = Color(0xFF0D0E12);

  /// rgba(13, 14, 18, 0.88) — the translucent overlay fill.
  static const Color backgroundGlass = Color(0xE00D0E12);

  /// Panel fill for cards, code blocks and the toolbar.
  static const Color panel = Color(0xFF14161D);

  /// Slightly lifted panel, used for hover states and inset code chrome.
  static const Color panelRaised = Color(0xFF1B1E27);

  /// rgba(255, 255, 255, 0.08) — the hairline border on every panel.
  static const Color border = Color(0x14FFFFFF);

  /// A marginally brighter hairline for focused/active panels.
  static const Color borderStrong = Color(0x26FFFFFF);

  // ------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF64748B);

  // ------------------------------------------------------------------ brand
  /// Royal Blue.
  static const Color accent = Color(0xFF4169E1);
  static const Color accentHover = Color(0xFF3B82F6);
  static const Color accentActive = Color(0xFF1D4ED8);

  /// 12% royal blue — accent chips and selected toolbar buttons.
  static const Color accentSoft = Color(0x1F4169E1);

  // ----------------------------------------------------------------- status
  /// Listening / connected.
  static const Color statusLive = Color(0xFF10B981);

  /// Muted / paused / error.
  static const Color statusMuted = Color(0xFFEF4444);

  /// Analyzing / thinking.
  static const Color statusThinking = Color(0xFFF59E0B);

  // ---------------------------------------------------------------- effects
  static const List<BoxShadow> panelShadow = <BoxShadow>[
    BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const Color scrim = Color(0x99000000);
}
