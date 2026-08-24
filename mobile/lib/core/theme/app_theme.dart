import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A workout is logged one row at a time — buttons and tap targets stay at
/// this height everywhere instead of each screen picking its own.
const double appStandardControlHeight = 48;
const double appCardRadius = 14;
const double appControlRadius = 12;

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColors.lightScheme, AppSemanticColors.light);
  static ThemeData get dark => _build(AppColors.darkScheme, AppSemanticColors.dark);

  static ThemeData _build(ColorScheme colorScheme, AppSemanticColors semantic) {
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [semantic],
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appCardRadius)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(appControlRadius))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(appStandardControlHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appControlRadius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(appStandardControlHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appControlRadius)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }
}
