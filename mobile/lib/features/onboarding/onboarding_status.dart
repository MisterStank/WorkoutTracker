import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../programs/fitness_profile_provider.dart';

/// What the first-run flow should do for a freshly-authenticated user whose
/// device hasn't recorded onboarding as complete.
class OnboardingDecision {
  const OnboardingDecision({required this.hasProfile, required this.hasProgram});

  final bool hasProfile;
  final bool hasProgram;

  /// A returning user (new device / reinstall) who already has a profile or
  /// a generated program shouldn't be walked through setup again.
  bool get isReturningUser => hasProfile || hasProgram;

  /// Whether the intro tour should still offer the "personalize a program"
  /// step. Skipped once the user already has either piece.
  bool get showPersonalization => !hasProfile && !hasProgram;
}

/// Pure decision helper — the single source of truth for the rules above,
/// kept testable without a network or a container.
OnboardingDecision decideOnboarding({required bool hasProfile, required bool hasProgram}) =>
    OnboardingDecision(hasProfile: hasProfile, hasProgram: hasProgram);

/// Resolves the decision from server state. Any fetch error is treated as
/// "new user" — showing the tour once too often is a smaller harm than
/// skipping setup for someone who needs it.
final onboardingDecisionProvider = FutureProvider<OnboardingDecision>((ref) async {
  final repo = ref.read(fitnessProfileRepositoryProvider);
  try {
    final results = await Future.wait([repo.myFitnessProfile(), repo.myPrograms()]);
    final profile = results[0];
    final programs = results[1] as List;
    return decideOnboarding(hasProfile: profile != null, hasProgram: programs.isNotEmpty);
  } catch (_) {
    return const OnboardingDecision(hasProfile: false, hasProgram: false);
  }
});
