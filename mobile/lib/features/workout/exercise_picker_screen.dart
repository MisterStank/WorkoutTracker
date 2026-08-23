import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_models.dart';
import 'workout_provider.dart';

/// Search-and-pick screen; pops with the selected Exercise, or null if the
/// user backs out. Surfaces recently-used exercises first so logging the
/// next set of an ongoing workout doesn't require typing a search every time.
class ExercisePickerScreen extends ConsumerStatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  ConsumerState<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  final _searchController = TextEditingController();
  List<Exercise> _exercises = [];
  bool _loading = true;
  String? _error;
  bool _searching = false;

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
    ref.read(recentExerciseIdsProvider.notifier).recordUse(exercise.id);
    Navigator.of(context).pop(exercise);
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

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search exercises…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          onChanged: _search,
        ),
      ),
      body: Builder(builder: (context) {
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null) return Center(child: Text('Error: $_error'));
        if (_exercises.isEmpty) {
          return const Center(child: Text('No exercises found'));
        }

        return ListView(
          children: [
            if (!_searching && recentExercises.isNotEmpty) ...[
              const _SectionHeader('Recent'),
              ...recentExercises.map((e) => _ExerciseTile(exercise: e, onTap: () => _select(e))),
              const Divider(height: 24),
              const _SectionHeader('All exercises'),
            ],
            ..._exercises.map((e) => _ExerciseTile(exercise: e, onTap: () => _select(e))),
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
  const _ExerciseTile({required this.exercise, required this.onTap});

  final Exercise exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.fitness_center, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 20),
      ),
      title: Text(exercise.name),
      subtitle: Text(exercise.category),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
