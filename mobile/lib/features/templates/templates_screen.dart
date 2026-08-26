import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workout/superset_provider.dart';
import '../workout/workout_provider.dart';
import 'create_template_screen.dart';
import 'template_models.dart';
import 'template_provider.dart';

/// Lists saved workout templates; tapping one starts a workout from it and
/// pops back to the home screen (which then shows the planned exercises).
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  late Future<List<WorkoutTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(templateRepositoryProvider).list();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateTemplateScreen()),
    );
    if (created == true) setState(_reload);
  }

  Future<void> _delete(String templateId) async {
    try {
      await ref.read(templateRepositoryProvider).delete(templateId);
      setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _start(WorkoutTemplate template) async {
    ref.read(activeSupersetsProvider.notifier).reset();
    await ref.read(activeWorkoutProvider.notifier).start(templateId: template.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
      body: FutureBuilder<List<WorkoutTemplate>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          final templates = snapshot.data ?? [];
          if (templates.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.checklist, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No templates yet. Save a plan once and start\nfrom it instead of picking exercises every time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${t.exercises.length} exercises'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(t.id),
                  ),
                  onTap: () => _start(t),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
