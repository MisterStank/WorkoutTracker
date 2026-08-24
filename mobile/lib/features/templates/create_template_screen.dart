import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workout/exercise_picker_screen.dart';
import '../workout/workout_models.dart';
import 'template_models.dart';
import 'template_provider.dart';

class CreateTemplateScreen extends ConsumerStatefulWidget {
  const CreateTemplateScreen({super.key});

  @override
  ConsumerState<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends ConsumerState<CreateTemplateScreen> {
  final _nameController = TextEditingController();
  final List<TemplateExerciseDraft> _exercises = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null) return;
    setState(() {
      _exercises.add(TemplateExerciseDraft(exerciseId: exercise.id, exerciseName: exercise.name, targetSets: 3));
    });
  }

  void _updateSets(int index, int delta) {
    setState(() {
      final current = _exercises[index];
      final next = (current.targetSets + delta).clamp(1, 10);
      _exercises[index] = TemplateExerciseDraft(
        exerciseId: current.exerciseId,
        exerciseName: current.exerciseName,
        targetSets: next,
        targetReps: current.targetReps,
      );
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _exercises.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(templateRepositoryProvider).create(name: name, exercises: _exercises);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty && _exercises.isNotEmpty && !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('New template')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Template name', hintText: 'e.g. Push day'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: _exercises.isEmpty
                ? Center(
                    child: Text('Add exercises to this plan', style: TextStyle(color: Colors.grey.shade600)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _exercises.length,
                    itemBuilder: (context, index) {
                      final ex = _exercises[index];
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(ex.exerciseName),
                          subtitle: Text('${ex.targetSets} sets'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _updateSets(index, -1)),
                              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _updateSets(index, 1)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() => _exercises.removeAt(index)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercise'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: canSave ? _save : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: _saving ? const CircularProgressIndicator() : const Text('Save template'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
