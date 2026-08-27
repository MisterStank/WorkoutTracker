/// Pure, dependency-free validators for the log-set form, mirroring the
/// backend's `service.ValidateSetInput` bounds so bad input is caught before
/// a round-trip. Each returns an error string for a `TextFormField.validator`,
/// or null when the value is acceptable.
///
/// Values are checked in the user's *display* unit; the bounds are unit-aware
/// because 1000 kg ≈ 2205 lb.
library;

/// Max weight in kg (backend cap). Callers pass the equivalent in their unit.
const double maxWeightKg = 1000;

String? validateReps(String? raw) {
  final value = int.tryParse((raw ?? '').trim());
  if (value == null) return 'Whole number';
  if (value < 1 || value > 100) return '1–100';
  return null;
}

/// [maxWeightInUnit] is [maxWeightKg] converted to the field's unit.
/// [allowNonPositive] is true for bodyweight exercises, where the field is
/// added load and may be 0 or negative (assisted).
String? validateWeight(String? raw, {required double maxWeightInUnit, bool allowNonPositive = false}) {
  final value = double.tryParse((raw ?? '').trim());
  if (value == null) return 'Number';
  if (!allowNonPositive && value < 0) return "Can't be negative";
  if (value.abs() > maxWeightInUnit) return 'Too heavy';
  return null;
}

String? validateRpe(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null; // RPE is optional
  final value = double.tryParse(trimmed);
  if (value == null) return 'Number';
  if (value < 1 || value > 10) return '1–10';
  if ((value * 2) % 1 != 0) return 'Use 0.5 steps';
  return null;
}
