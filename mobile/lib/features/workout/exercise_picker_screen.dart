import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'create_exercise_screen.dart';
import 'exercise_category_icon.dart';
import 'exercise_detail_sheet.dart';
import 'workout_models.dart';
import 'workout_provider.dart';

/// Search-and-pick screen; pops with the selected Exercise, or null if the
/// user backs out. Surfaces recently-used exercises first so logging the
/// next set of an ongoing workout doesn't require typing a search every time.
///
/// When [multiSelect] is true, tapping a row toggles a checkbox instead of
/// popping immediately; a "Done" action pops with a `List<Exercise>` (2+
/// required) instead of a single `Exercise` — used for grouping an ad-hoc
/// mid-workout superset.
class ExercisePickerScreen extends ConsumerStatefulWidget {
  const ExercisePickerScreen({super.key, this.multiSelect = false});

  final bool multiSelect;

  @override
  ConsumerState<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  final _searchController = TextEditingController();
  List<Exercise> _exercises = [];
  bool _loading = true;
  String? _error;
  bool _searching = false;
  final Map<String, Exercise> _selected = {};

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
      _searching = query.trim().isNotEmpty;
    });
    try {
      final results = await ref.read(workoutRepositoryProvider).exercises(search: query.isEmpty ? null : query);
      setState(() {
        _exercises = results;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _select(Exercise exercise) {
    if (widget.multiSelect) {
      setState(() {
        if (_selected.remove(exercise.id) == null) {
          _selected[exercise.id] = exercise;
        }
      });
      return;
    }
    ref.read(recentExerciseIdsProvider.notifier).recordUse(exercise.id);
    Navigator.of(context).pop(exercise);
  }

  Future<void> _openEditor({Exercise? initial, String? initialName}) async {
    final saved = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => CreateExerciseScreen(initial: initial, initialName: initialName)),
    );
    if (saved != null && mounted) {
      _searchController.text = saved.name;
      await _search(saved.name);
    }
  }

  Future<void> _manageCustom(Exercise exercise) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit exercise'), onTap: () => Navigator.pop(context, 'edit')),
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete exercise'), onTap: () => Navigator.pop(context, 'delete')),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _openEditor(initial: exercise);
    } else if (action == 'delete' && mounted) {
      try {
        await ref.read(workoutRepositoryProvider).deleteExercise(exercise.id);
        ref.invalidate(exerciseCatalogProvider);
        await _search(_searchController.text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
        }
      }
    }
  }

  void _confirmMultiSelect() {
    if (_selected.length < 2) return;
    for (final e in _selected.values) {
      ref.read(recentExerciseIdsProvider.notifier).recordUse(e.id);
    }
    Navigator.of(context).pop(_selected.values.toList());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentIds = ref.watch(recentExerciseIdsProvider);
    final byId = {for (final e in _exercises) e.id: e};
    final recentExercises = recentIds.map((id) => byId[id]).whereType<Exercise>().toList();

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search exercises…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          style: TextStyle(color: colorScheme.onSurface),
          cursorColor: colorScheme.primary,
          onChanged: _search,
        ),
        actions: widget.multiSelect
            ? [
                TextButton(
                  onPressed: _selected.length >= 2 ? _confirmMultiSelect : null,
                  child: Text('Done (${_selected.length})'),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New exercise',
                  onPressed: () => _openEditor(),
                ),
              ],
      ),
      body: Builder(builder: (context) {
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null) return Center(child: Text('Error: $_error'));
        if (_exercises.isEmpty) {
          final query = _searchController.text.trim();
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No exercises found'),
                if (query.isNotEmpty && !widget.multiSelect) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openEditor(initialName: query),
                    icon: const Icon(Icons.add),
                    label: Text('Create "$query"'),
                  ),
                ],
              ],
            ),
          );
        }

        return ListView(
          children: [
            if (!_searching && recentExercises.isNotEmpty) ...[
              const _SectionHeader('Recent'),
              ...recentExercises.map((e) => _ExerciseTile(
                    exercise: e,
                    onTap: () => _select(e),
                    selected: widget.multiSelect ? _selected.containsKey(e.id) : null,
                  )),
              const Divider(height: 24),
              const _SectionHeader('All exercises'),
            ],
            ..._exercises.map((e) => _ExerciseTile(
                  exercise: e,
                  onTap: () => _select(e),
                  onLongPress: e.isCustom && !widget.multiSelect ? () => _manageCustom(e) : null,
                  selected: widget.multiSelect ? _selected.containsKey(e.id) : null,
                )),
          ],
        );
      }),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.onTap, this.onLongPress, this.selected});

  final Exercise exercise;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // Null when not in multi-select mode (plain chevron row).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GestureDetector(
        onTap: () => showExerciseDetailSheet(context, exercise),
        child: ExerciseCategoryIcon(category: exercise.category),
      ),
      title: Text(exercise.name),
      subtitle: Text(exercise.isCustom ? '${exercise.category} · custom (long-press to edit)' : exercise.category),
      onLongPress: onLongPress,
      trailing: selected == null
          ? const Icon(Icons.chevron_right)
          : Icon(
              selected! ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected! ? Theme.of(context).colorScheme.primary : null,
            ),
      selected: selected ?? false,
      onTap: onTap,
    );
  }
}
