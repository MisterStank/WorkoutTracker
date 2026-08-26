import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../templates/template_models.dart';
import '../templates/template_provider.dart';
import 'fitness_profile_provider.dart';

class _DraftDay {
  _DraftDay({required this.templateId, required this.labelController});

  final String templateId;
  final TextEditingController labelController;
}

/// Manually assemble a Program out of the user's own existing templates —
/// the alternative to the AI questionnaire (FitnessProfileScreen) for
/// getting a program onto the Programs tab.
class BuildProgramScreen extends ConsumerStatefulWidget {
  const BuildProgramScreen({super.key});

  @override
  ConsumerState<BuildProgramScreen> createState() => _BuildProgramScreenState();
}

class _BuildProgramScreenState extends ConsumerState<BuildProgramScreen> {
  final _nameController = TextEditingController();
  final _days = <_DraftDay>[];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    for (final d in _days) {
      d.labelController.dispose();
    }
    super.dispose();
  }

  Future<void> _addDay() async {
    final templates = await ref.read(templateRepositoryProvider).list();
    if (!mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save a template first, then add it to a program here.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<WorkoutTemplate>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Pick a template', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  return ListTile(
                    title: Text(t.name),
                    subtitle: Text('${t.exercises.length} exercises'),
                    onTap: () => Navigator.of(context).pop(t),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _days.add(_DraftDay(templateId: picked.id, labelController: TextEditingController(text: picked.name)));
    });
  }

  void _removeDay(int index) {
    setState(() {
      _days.removeAt(index).labelController.dispose();
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the program a name and at least one day.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(fitnessProfileRepositoryProvider).createProgramFromTemplates(
            name,
            [for (final d in _days) (d.labelController.text.trim().isEmpty ? 'Day' : d.labelController.text.trim(), d.templateId)],
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create program: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Build a program')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDay,
        icon: const Icon(Icons.add),
        label: const Text('Add day'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Program name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          if (_days.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No days yet. Tap "Add day" to pick one of your\nsaved templates and add it to this program.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _days.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final d = _days.removeAt(oldIndex);
                  _days.insert(newIndex, d);
                });
              },
              itemBuilder: (context, index) {
                final day = _days[index];
                return Card(
                  key: ValueKey(day),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                    title: TextField(
                      controller: day.labelController,
                      decoration: const InputDecoration(labelText: 'Day label', isDense: true),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeDay(index),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create program'),
          ),
        ],
      ),
    );
  }
}
