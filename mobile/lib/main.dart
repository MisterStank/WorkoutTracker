import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show initHiveForFlutter;

import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/onboarding_prefs.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/onboarding_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHiveForFlutter();
  final seenOnboarding = await loadOnboardingComplete();
  runApp(
    ProviderScope(
      overrides: [onboardingCompleteProvider.overrideWith((ref) => seenOnboarding)],
      child: const WorkoutTrackerApp(),
    ),
  );
}

class WorkoutTrackerApp extends ConsumerWidget {
  const WorkoutTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'WorkoutTracker',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: const AuthGate(),
    );
  }
}

/// Routes to the login screen, the first-run onboarding tutorial, or the
/// app's bottom-nav shell, based on authProvider's state and whether this
/// device has completed onboarding yet.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState is AuthRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authState is AuthAuthenticated) {
      if (ref.watch(onboardingCompleteProvider)) return const AppShell();

      // Device hasn't seen onboarding — but the account might already be set
      // up (returning user on a new device). Check server state before
      // deciding whether to run the tour.
      return ref.watch(onboardingDecisionProvider).when(
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (_, _) => const OnboardingScreen(showPersonalization: true),
            data: (decision) {
              if (decision.isReturningUser) {
                // Defer the state write so we don't mutate a provider while
                // this widget is still building.
                Future.microtask(() => markOnboardingComplete(ref));
                return const AppShell();
              }
              return OnboardingScreen(showPersonalization: decision.showPersonalization);
            },
          );
    }

    return const LoginScreen();
  }
}
