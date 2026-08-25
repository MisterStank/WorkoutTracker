import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_profile_models.dart';
import 'fitness_profile_provider.dart';
import 'program_review_screen.dart';

/// Every program the user has generated, newest first — the piece that was
/// missing before: generateProgram() persists a Program (and its days as
/// ordinary templates), but nothing showed it as one grouped thing again
/// after the one-time review screen right after generating. This list is
/// that missing "where did it go" answer.
class ProgramsListScreen extends ConsumerStatefulWidget {
  const ProgramsListScreen({super.key});

  @override
  ConsumerState<ProgramsListScreen> createState() => _ProgramsListScreenState();
}

class _ProgramsListScreenState extends ConsumerState<ProgramsListScreen> {
  late Future<List<Program>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(fitnessProfileRepositoryProvider).myPrograms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Programs')),
      body: FutureBuilder<List<Program>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      "No programs generated yet. Tap the sparkle icon on\nTemplates to answer a few questions and get one.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: programs.length,
            itemBuilder: (context, index) {
              final p = programs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p.daysPerWeek} days a week · ${p.goal.label} · ${p.days.length} template${p.days.length == 1 ? '' : 's'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgramReviewScreen(program: p))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
