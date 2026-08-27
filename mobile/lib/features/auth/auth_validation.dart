/// Pure client-side auth checks, mirroring the backend's `service.Validate*`
/// so obvious mistakes get instant feedback without a round-trip. The server
/// remains the source of truth and returns its own clean messages.
library;

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns an error message, or null if the email looks valid.
String? validateEmail(String raw) {
  final value = raw.trim().toLowerCase();
  if (!_emailPattern.hasMatch(value)) return 'Enter a valid email address';
  return null;
}

/// Returns an error message, or null if the password meets the minimum.
String? validatePassword(String raw) {
  if (raw.length < 8) return 'Password must be at least 8 characters';
  return null;
}

/// Returns an error message, or null if the display name is non-empty.
String? validateDisplayName(String raw) {
  if (raw.trim().isEmpty) return 'Enter a display name';
  return null;
}

/// First failing check across signup fields, or null when all pass.
String? validateSignup({required String email, required String password, required String displayName}) {
  return validateDisplayName(displayName) ?? validateEmail(email) ?? validatePassword(password);
}
