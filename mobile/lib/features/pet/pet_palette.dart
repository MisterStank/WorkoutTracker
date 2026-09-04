import 'dart:ui';

import 'pet_models.dart';

/// The companion is drawn monochrome: one soft pastel per [PetColor], with the
/// belly / species feature / outline all derived from it so recolouring stays
/// clean. This is placeholder art — replaced by hand-drawn assets per
/// docs/PET_PLAN.md.
class PetPalette {
  PetPalette(this.body)
      : belly = _shift(body, 0.22),
        feature = _shift(body, 0.12),
        outline = _shift(body, -0.42);

  /// Main body colour.
  final Color body;

  /// Lighter — the belly patch.
  final Color belly;

  /// Slightly lighter — the leaf / flame / rock / cloud on the head.
  final Color feature;

  /// Darkened — the thin outline and the face ink.
  final Color outline;

  /// Blend [c] toward white (positive [amount]) or black (negative).
  static Color _shift(Color c, double amount) {
    final t = amount.abs();
    final target = amount >= 0 ? 1.0 : 0.0;
    double m(double v) => v + (target - v) * t;
    return Color.from(alpha: 1, red: m(c.r), green: m(c.g), blue: m(c.b));
  }
}

const _pastels = <PetColor, Color>{
  PetColor.green: Color(0xFF8FD9B0), // mint
  PetColor.red: Color(0xFFF3958A), // coral
  PetColor.blue: Color(0xFF8FC2F0), // sky
  PetColor.amber: Color(0xFFF3CE86), // butter
  PetColor.violet: Color(0xFFC4A6ED), // lavender
};

PetPalette petPalette(PetColor color) => PetPalette(_pastels[color]!);

/// Drained + slightly greyed, for a neglected companion.
PetPalette neglectedPalette(PetColor color) {
  final base = _pastels[color]!;
  final grey = Color.lerp(base, const Color(0xFFB6B2AE), 0.62)!;
  return PetPalette(grey);
}

/// The dot shown in colour pickers — the body pastel for that choice.
Color petColorSwatch(PetColor color) => _pastels[color]!;
