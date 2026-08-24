import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show initHiveForFlutter;

import 'core/navigation/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHiveForFlutter();
  runApp(const ProviderScope(child: WorkoutTrackerApp()));
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

/// Routes to the login screen or the app's bottom-nav shell, based purely on
/// authProvider's current state.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState is AuthRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authState is AuthAuthenticated) {
      return const AppShell();
    }

    return const LoginScreen();
  }
}
