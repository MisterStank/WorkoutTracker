import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_models.dart';
import 'workout_provider.dart';

class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  final List<Workout> _workouts = [];
  String? _cursor;
  bool _hasNextPage = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNextPage) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(workoutRepositoryProvider).workoutHistory(first: 20, after: _cursor);
      setState(() {
        _workouts.addAll(page.workouts);
        _cursor = page.endCursor;
        _hasNextPage = page.hasNextPage;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: _error != null
          ? Center(child: Text('Error: $_error'))
          : _workouts.isEmpty && !_loading
              ? const Center(child: Text('No workouts yet'))
              : NotificationListener<ScrollEndNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 200) _loadMore();
                    return false;
                  },
                  child: ListView.builder(
                    itemCount: _workouts.length + (_hasNextPage ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _workouts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final workout = _workouts[index];
                      return ListTile(
                        title: Text('${workout.startedAt.toLocal()}'.split('.').first),
                        subtitle: Text('${workout.sets.length} sets${workout.notes.isEmpty ? '' : ' · ${workout.notes}'}'),
                      );
                    },
                  ),
                ),
    );
  }
}
