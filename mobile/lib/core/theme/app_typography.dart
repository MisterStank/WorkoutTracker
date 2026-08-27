import 'package:flutter/material.dart';

/// The app's type system, kept out of [AppTheme] so that file stays a plain
/// config surface.
///
/// - **Barlow** — body text, labels, buttons (set as `ThemeData.fontFamily`).
/// - **Barlow Semi Condensed** — the wordmark and every heading / title /
///   AppBar, for a compact athletic voice that also matches the printed
///   manual.
/// - **IBM Plex Mono** — logged numbers (weights, reps, RPE, timers, stat
///   tiles), so columns of data line up and read like an instrument.
///
/// All three are bundled in `assets/fonts/` (see `pubspec.yaml`); nothing is
/// fetched at runtime.
class AppTypography {
  AppTypography._();

  static const String body = 'Barlow';
  static const String display = 'BarlowSemiCondensed';
  static const String mono = 'IBMPlexMono';

  /// Monospace style for numeric values. Callers `.copyWith` size / weight /
  /// colour — e.g. `AppTypography.monoText.copyWith(fontSize: 14)` or, when
  /// starting from a themed style, `style.copyWith(fontFamily: AppTypography.mono)`.
  static const TextStyle monoText = TextStyle(
    fontFamily: mono,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Layers the family choices onto a base [TextTheme]: display / headline /
  /// title roles become Barlow Semi Condensed with tight tracking at the big
  /// sizes; body and label roles inherit Barlow from `ThemeData.fontFamily`,
  /// so only weight bumps live here.
  static TextTheme textTheme(TextTheme base) => base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        displayMedium: base.displayMedium?.copyWith(fontFamily: display, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        displaySmall: base.displaySmall?.copyWith(fontFamily: display, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        headlineLarge: base.headlineLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        headlineMedium: base.headlineMedium?.copyWith(fontFamily: display, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        headlineSmall: base.headlineSmall?.copyWith(fontFamily: display, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleLarge: base.titleLarge?.copyWith(fontFamily: display, fontWeight: FontWeight.w700),
        titleMedium: base.titleMedium?.copyWith(fontFamily: display, fontWeight: FontWeight.w600),
        titleSmall: base.titleSmall?.copyWith(fontFamily: display, fontWeight: FontWeight.w600),
        // labelLarge drives button text — keep it Barlow, just a touch heavier.
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      );
}
