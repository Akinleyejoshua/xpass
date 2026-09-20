import 'package:flutter/material.dart';

import 'colors.dart';

/// Typography for the HUD.
///
/// Both families are bundled under `assets/fonts`, so first paint never waits
/// on a network fetch — important when the HUD is summoned mid-sentence.
/// [XpType.displayFamily] is Bricolage Grotesque; code and complexity readouts
/// use JetBrains Mono.
abstract final class XpType {
  static const String displayFamily = 'BricolageGrotesque';
  static const String monoFamily = 'JetBrainsMono';

  // ---------------------------------------------------------------- headings
  static const TextStyle title = TextStyle(
    fontFamily: displayFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: XpColors.textPrimary,
  );

  static const TextStyle sectionHeading = TextStyle(
    fontFamily: displayFamily,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: XpColors.accentHover,
  );

  /// Small uppercase label used on chips, status pills and toolbar hints.
  static const TextStyle label = TextStyle(
    fontFamily: displayFamily,
    fontSize: 10,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: XpColors.textSecondary,
  );

  // ------------------------------------------------------------------- body
  static const TextStyle body = TextStyle(
    fontFamily: displayFamily,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: XpColors.textPrimary,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: displayFamily,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: XpColors.textSecondary,
  );

  /// The "say this now" line — the one thing the user reads under pressure.
  static const TextStyle verbal = TextStyle(
    fontFamily: displayFamily,
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w600,
    color: XpColors.textPrimary,
  );

  // -------------------------------------------------------------------- mono
  static const TextStyle code = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12.5,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: XpColors.textPrimary,
  );

  static const TextStyle codeInline = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12.5,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: XpColors.accentHover,
  );

  /// Latency metric / complexity readout.
  static const TextStyle metric = TextStyle(
    fontFamily: monoFamily,
    fontSize: 10,
    height: 1.1,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: XpColors.textTertiary,
  );
}

/// Dark [ThemeData] wired to the xpass tokens.
ThemeData buildXpassTheme() {
  final ColorScheme scheme = const ColorScheme.dark().copyWith(
    primary: XpColors.accent,
    secondary: XpColors.accentHover,
    surface: XpColors.panel,
    error: XpColors.statusMuted,
    onPrimary: XpColors.textPrimary,
    onSurface: XpColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    fontFamily: XpType.displayFamily,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 420),
      textStyle: TextStyle(
        fontFamily: XpType.displayFamily,
        fontSize: 11,
        color: XpColors.textPrimary,
      ),
      decoration: BoxDecoration(
        color: XpColors.panelRaised,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(XpColors.border),
      thickness: const WidgetStatePropertyAll<double>(4),
      radius: const Radius.circular(4),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: XpColors.accent,
      selectionColor: XpColors.accentSoft,
      selectionHandleColor: XpColors.accent,
    ),
  );
}
