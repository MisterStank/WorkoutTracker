import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../templates/templates_screen.dart';
import 'build_program_screen.dart';
import 'fitness_profile_models.dart';
import 'fitness_profile_provider.dart';
import 'fitness_profile_screen.dart';
import 'program_review_screen.dart';

/// The Programs tab: every program the user has (AI-generated or manually
/// built from existing templates, mixed together — both are just Program
/// rows, no schema distinction), newest first. Template management (create/
/// list/delete standalone templates) has moved off the bottom nav and lives
/// behind the library icon here instead.
class ProgramsScreen extends ConsumerStatefulWidget {
  const ProgramsScreen({super.key});

  @override
  ConsumerState<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends ConsumerState<ProgramsScreen> {
  late Future<List<Program>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(fitnessProfileRepositoryProvider).myPrograms();
  }

  Future<void> _generate() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FitnessProfileScreen()));
    if (mounted) setState(_reload);
  }

  Future<void> _build() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BuildProgramScreen()),
    );
    if (created == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Template library',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Build a program from templates',
            onPressed: _build,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate a program',
            onPressed: _generate,
          ),
        ],
      ),
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
                    Icon(Icons.calendar_view_month, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      "No programs yet. Tap the sparkle icon to answer a\nfew questions and generate one, or the + icon to\nbuild one from your own templates.",
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
                color: p.isActive ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
                child: ListTile(
                  leading: p.isActive ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : const Icon(Icons.calendar_view_month, color: Colors.transparent),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p.daysPerWeek} days a week · ${p.goal.label} · ${p.days.length} template${p.days.length == 1 ? '' : 's'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgramReviewScreen(program: p)));
                    if (mounted) setState(_reload);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
