import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _onboardingCompleteKey = 'onboarding_complete';

// Reuses flutter_secure_storage (already a dependency, used for auth tokens)
// rather than adding shared_preferences: that package broke this app's web
// release build with an unhandled exception during boot (reproducible 3/3
// with it present, 0/2 without — root-caused via a debug-vs-release-build
// comparison and an isolation test removing just that one dependency). A
// plain on/off flag doesn't need "secure" storage semantically, but reusing
// a proven-working mechanism beats debugging a third-party plugin conflict.
const _storage = FlutterSecureStorage();

/// Whether this device has already seen (or skipped) the first-run
/// onboarding tutorial. Seeded once at startup (see main()) rather than
/// read lazily, so AuthGate never needs an extra loading state beyond the
/// existing auth-restoring one.
final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

/// Reads the persisted flag. Called once during app startup, before
/// runApp, to seed [onboardingCompleteProvider]'s initial value.
Future<bool> loadOnboardingComplete() async {
  final value = await _storage.read(key: _onboardingCompleteKey);
  return value == 'true';
}

/// Marks onboarding as done: flips the provider immediately (so the UI
/// reacts right away) and persists in the background.
void markOnboardingComplete(WidgetRef ref) {
  ref.read(onboardingCompleteProvider.notifier).state = true;
  _storage.write(key: _onboardingCompleteKey, value: 'true');
}
