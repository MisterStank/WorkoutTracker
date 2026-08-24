import 'package:flutter/material.dart';

/// The app's brand seed: a grounded, iron/rust-toned brick red rather than a
/// stop-sign red — chosen so it reads as premium athletic gear, not a
/// warning label, and so it doesn't collide with the "failure" set-type
/// badge (see [AppSemanticColors.setFailure], deliberately not red).
const _seedRed = Color(0xFF9B2C2C);

class AppColors {
  AppColors._();

  static const primaryLight = Color(0xFF9B2C2C);
  static const onPrimaryLight = Color(0xFFFFF5F2);

  // Material 3 always lightens/desaturates a seed's primary for dark
  // surfaces — never reuse the light-mode primary as-is here, it would fail
  // contrast against a dark background.
  static const primaryDark = Color(0xFFE8A198);
  static const onPrimaryDark = Color(0xFF5C1512);

  static final lightScheme = ColorScheme.fromSeed(
    seedColor: _seedRed,
    brightness: Brightness.light,
  ).copyWith(primary: primaryLight, onPrimary: onPrimaryLight);

  static final darkScheme = ColorScheme.fromSeed(
    seedColor: _seedRed,
    brightness: Brightness.dark,
  ).copyWith(primary: primaryDark, onPrimary: onPrimaryDark);
}

/// Semantic colors the base [ColorScheme] has no slot for — banners and
/// set-type badges. Kept deliberately separate from [AppColors.primaryLight]
/// / [AppColors.primaryDark] (the brand red) so "this is the app" and "this
/// went well / needs attention / failed" never share a hue and get
/// confused for one another.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.setWarmupContainer,
    required this.onSetWarmupContainer,
    required this.setDropsetContainer,
    required this.onSetDropsetContainer,
    required this.setFailureContainer,
    required this.onSetFailureContainer,
  });

  /// Personal-record / achievement banners. Gold, not brand red — a PR is a
  /// trophy moment, not "the app's color happened to show up here."
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Plateau notices and other "worth a second look" callouts.
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Neutral guidance — rest timer, progression suggestions.
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  final Color setWarmupContainer;
  final Color onSetWarmupContainer;
  final Color setDropsetContainer;
  final Color onSetDropsetContainer;

  /// Deliberately plum/violet, not red or orange — red is the brand color
  /// and orange is already used for drop sets, so "failure" needed a third,
  /// unrelated hue to stay visually distinct from both.
  final Color setFailureContainer;
  final Color onSetFailureContainer;

  static const light = AppSemanticColors(
    success: Color(0xFFA9720A),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFFBE8C6),
    onSuccessContainer: Color(0xFF4A3200),
    warning: Color(0xFF92600A),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF6E4BE),
    onWarningContainer: Color(0xFF3D2900),
    info: Color(0xFF3F5B72),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDCEAF3),
    onInfoContainer: Color(0xFF0B2430),
    setWarmupContainer: Color(0xFFE4E9F0),
    onSetWarmupContainer: Color(0xFF33475B),
    setDropsetContainer: Color(0xFFF7DFB8),
    onSetDropsetContainer: Color(0xFF5C3B00),
    setFailureContainer: Color(0xFFE6DCEA),
    onSetFailureContainer: Color(0xFF4A2E55),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFFDDB668),
    onSuccess: Color(0xFF412D00),
    successContainer: Color(0xFF5C4300),
    onSuccessContainer: Color(0xFFFBE8C6),
    warning: Color(0xFFD9B67C),
    onWarning: Color(0xFF3D2900),
    warningContainer: Color(0xFF573D0A),
    onWarningContainer: Color(0xFFF6E4BE),
    info: Color(0xFFA9C7DC),
    onInfo: Color(0xFF0B2430),
    infoContainer: Color(0xFF294254),
    onInfoContainer: Color(0xFFDCEAF3),
    setWarmupContainer: Color(0xFF33475B),
    onSetWarmupContainer: Color(0xFFD3DFEC),
    setDropsetContainer: Color(0xFF5C3B00),
    onSetDropsetContainer: Color(0xFFF7DFB8),
    setFailureContainer: Color(0xFF4A2E55),
    onSetFailureContainer: Color(0xFFE6DCEA),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? setWarmupContainer,
    Color? onSetWarmupContainer,
    Color? setDropsetContainer,
    Color? onSetDropsetContainer,
    Color? setFailureContainer,
    Color? onSetFailureContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      setWarmupContainer: setWarmupContainer ?? this.setWarmupContainer,
      onSetWarmupContainer: onSetWarmupContainer ?? this.onSetWarmupContainer,
      setDropsetContainer: setDropsetContainer ?? this.setDropsetContainer,
      onSetDropsetContainer: onSetDropsetContainer ?? this.onSetDropsetContainer,
      setFailureContainer: setFailureContainer ?? this.setFailureContainer,
      onSetFailureContainer: onSetFailureContainer ?? this.onSetFailureContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      setWarmupContainer: Color.lerp(setWarmupContainer, other.setWarmupContainer, t)!,
      onSetWarmupContainer: Color.lerp(onSetWarmupContainer, other.onSetWarmupContainer, t)!,
      setDropsetContainer: Color.lerp(setDropsetContainer, other.setDropsetContainer, t)!,
      onSetDropsetContainer: Color.lerp(onSetDropsetContainer, other.onSetDropsetContainer, t)!,
      setFailureContainer: Color.lerp(setFailureContainer, other.setFailureContainer, t)!,
      onSetFailureContainer: Color.lerp(onSetFailureContainer, other.onSetFailureContainer, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors => Theme.of(this).extension<AppSemanticColors>()!;
}
