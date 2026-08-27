import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../programs/fitness_profile_models.dart' show availableEquipment, availableMuscleGroups;
import 'workout_models.dart';
import 'workout_provider.dart';

const _categories = ['push', 'pull', 'legs', 'arms', 'core'];

/// Create or edit a user-owned custom exercise. Pops with the saved
/// [Exercise] on success, or null if cancelled.
class CreateExerciseScreen extends ConsumerStatefulWidget {
  const CreateExerciseScreen({super.key, this.initial, this.initialName});

  /// When set, the screen edits this exercise instead of creating one.
  final Exercise? initial;

  /// Pre-fills the name field for the "create from search" shortcut.
  final String? initialName;

  @override
  ConsumerState<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends ConsumerState<CreateExerciseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _category;
  late String _equipment;
  late final Set<String> _muscleGroups;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? widget.initialName ?? '');
    _category = initial != null && _categories.contains(initial.category) ? initial.category : _categories.first;
    _equipment = initial != null && availableEquipment.contains(initial.equipment) ? initial.equipment : availableEquipment.first;
    _muscleGroups = {...?initial?.muscleGroups};
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(workoutRepositoryProvider);
    try {
      final saved = _isEditing
          ? await repo.updateExercise(
              exerciseId: widget.initial!.id,
              name: _nameController.text.trim(),
              category: _category,
              muscleGroups: _muscleGroups.toList(),
              equipment: _equipment,
            )
          : await repo.createExercise(
              name: _nameController.text.trim(),
              category: _category,
              muscleGroups: _muscleGroups.toList(),
              equipment: _equipment,
            );
      ref.invalidate(exerciseCatalogProvider);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit exercise' : 'New exercise')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.edit_outlined)),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name' : null,
            ),
            const SizedBox(height: 20),
            Text('Category', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _categories
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text('Equipment', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: availableEquipment
                  .map((e) => ChoiceChip(
                        label: Text(e),
                        selected: _equipment == e,
                        onSelected: (_) => setState(() => _equipment = e),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text('Muscle groups (optional)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: availableMuscleGroups
                  .map((m) => FilterChip(
                        label: Text(m),
                        selected: _muscleGroups.contains(m),
                        onSelected: (v) => setState(() => v ? _muscleGroups.add(m) : _muscleGroups.remove(m)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Create exercise'),
            ),
          ],
        ),
      ),
    );
  }
}
