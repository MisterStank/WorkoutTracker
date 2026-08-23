import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_models.dart';
import 'workout_provider.dart';

/// Search-and-pick screen; pops with the selected Exercise, or null if the
/// user backs out.
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

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search exercises...', border: InputBorder.none),
          onSubmitted: _search,
        ),
      ),
      body: Builder(builder: (context) {
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null) return Center(child: Text('Error: $_error'));
        if (_exercises.isEmpty) return const Center(child: Text('No exercises found'));
        return ListView.builder(
          itemCount: _exercises.length,
          itemBuilder: (context, index) {
            final exercise = _exercises[index];
            return ListTile(
              title: Text(exercise.name),
              subtitle: Text(exercise.category),
              onTap: () => Navigator.of(context).pop(exercise),
            );
          },
        );
      }),
    );
  }
}
