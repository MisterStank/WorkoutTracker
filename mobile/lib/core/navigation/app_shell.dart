import 'package:flutter/material.dart';

import '../../features/analytics/analytics_screen.dart';
import '../../features/templates/templates_screen.dart';
import '../../features/workout/workout_history_screen.dart';
import '../../features/workout/workout_home_screen.dart';

/// The app's persistent shell: a bottom nav bar over the four top-level
/// destinations, with an IndexedStack (not push navigation) so switching
/// tabs never loses an in-progress workout or the analytics screen's
/// selected chart.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = [
    WorkoutHomeScreen(),
    WorkoutHistoryScreen(),
    TemplatesScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Templates'),
          NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.show_chart), label: 'Progress'),
        ],
      ),
    );
  }
}
