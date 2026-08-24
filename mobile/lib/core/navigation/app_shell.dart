import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/analytics/analytics_screen.dart';
import '../../features/templates/templates_screen.dart';
import '../../features/workout/elapsed_time_text.dart';
import '../../features/workout/workout_history_screen.dart';
import '../../features/workout/workout_home_screen.dart';
import '../../features/workout/workout_models.dart';
import '../../features/workout/workout_provider.dart';
import '../../features/workout/workout_state.dart';

/// The app's persistent shell: a bottom nav bar over the four top-level
/// destinations, with an IndexedStack (not push navigation) so switching
/// tabs never loses an in-progress workout or the analytics screen's
/// selected chart. Also shows a "resume workout" strip above the nav bar
/// whenever a workout is running and the user has wandered off the Home
/// tab — otherwise there'd be no sign anywhere that a session is still
/// going.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _tabs = [
    WorkoutHomeScreen(),
    WorkoutHistoryScreen(),
    TemplatesScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final workoutState = ref.watch(activeWorkoutProvider);
    final activeWorkout = workoutState is ActiveWorkoutInProgress ? workoutState.workout : null;
    final showResumeBar = activeWorkout != null && _index != 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showResumeBar) _ResumeWorkoutBar(workout: activeWorkout, onTap: () => setState(() => _index = 0)),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
              NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Templates'),
              NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.show_chart), label: 'Progress'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumeWorkoutBar extends StatelessWidget {
  const _ResumeWorkoutBar({required this.workout, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.fitness_center, size: 18, color: colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Workout in progress',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onPrimaryContainer),
                ),
              ),
              ElapsedTimeText(
                startedAt: workout.startedAt,
                style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              Text(
                '${workout.sets.length} sets',
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colorScheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
