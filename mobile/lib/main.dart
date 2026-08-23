import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart' show initHiveForFlutter;

import 'features/auth/auth_provider.dart';
import 'features/auth/auth_state.dart';
import 'features/auth/login_screen.dart';
import 'features/workout/workout_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHiveForFlutter();
  runApp(const ProviderScope(child: WorkoutTrackerApp()));
}

class WorkoutTrackerApp extends StatelessWidget {
  const WorkoutTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkoutTracker',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const AuthGate(),
    );
  }
}

/// Routes to the login screen or the workout home screen, based purely on
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
      return const WorkoutHomeScreen();
    }

    return const LoginScreen();
  }
}
