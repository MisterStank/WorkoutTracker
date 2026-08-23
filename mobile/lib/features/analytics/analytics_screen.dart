import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/units_provider.dart';
import '../workout/exercise_picker_screen.dart';
import '../workout/workout_models.dart';
import 'analytics_models.dart';
import 'analytics_provider.dart';
import 'progress_chart.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Volume'),
            Tab(text: 'By exercise'),
            Tab(text: 'Body weight'),
          ]),
        ),
        body: const TabBarView(children: [
          _VolumeTrendTab(),
          _ExerciseProgressTab(),
          _BodyWeightTab(),
        ]),
      ),
    );
  }
}

class _VolumeTrendTab extends ConsumerStatefulWidget {
  const _VolumeTrendTab();

  @override
  ConsumerState<_VolumeTrendTab> createState() => _VolumeTrendTabState();
}

class _VolumeTrendTabState extends ConsumerState<_VolumeTrendTab> {
  late Future<List<ProgressPoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(analyticsRepositoryProvider).volumeTrend(days: 90);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProgressPoint>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final points = snapshot.data ?? [];
        if (points.isEmpty) {
          return const _EmptyChartHint(message: 'Log a few sets to see your training volume over time.');
        }
        final unit = ref.watch(weightUnitProvider);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ProgressChart(
            points: points,
            valueOf: (p) => unit.fromKg(p.totalVolume),
            label: 'Total volume (${unit.label})',
          ),
        );
      },
    );
  }
}

class _ExerciseProgressTab extends ConsumerStatefulWidget {
  const _ExerciseProgressTab();

  @override
  ConsumerState<_ExerciseProgressTab> createState() => _ExerciseProgressTabState();
}

class _ExerciseProgressTabState extends ConsumerState<_ExerciseProgressTab> {
  Exercise? _selected;
  Future<List<ProgressPoint>>? _future;

  Future<void> _pickExercise() async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null) return;
    setState(() {
      _selected = exercise;
      _future = ref.read(analyticsRepositoryProvider).progressOverTime(exerciseId: exercise.id, days: 90);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: _pickExercise,
            icon: const Icon(Icons.fitness_center),
            label: Text(_selected == null ? 'Choose an exercise' : _selected!.name),
          ),
        ),
        Expanded(
          child: _future == null
              ? const _EmptyChartHint(message: 'Pick an exercise to see its heaviest weight over time.')
              : FutureBuilder<List<ProgressPoint>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                    final points = snapshot.data ?? [];
                    if (points.isEmpty) {
                      return const _EmptyChartHint(message: 'No sets logged for this exercise yet.');
                    }
                    final unit = ref.watch(weightUnitProvider);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ProgressChart(
                        points: points,
                        valueOf: (p) => unit.fromKg(p.maxWeight),
                        label: 'Heaviest weight (${unit.label})',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BodyWeightTab extends ConsumerStatefulWidget {
  const _BodyWeightTab();

  @override
  ConsumerState<_BodyWeightTab> createState() => _BodyWeightTabState();
}

class _BodyWeightTabState extends ConsumerState<_BodyWeightTab> {
  Future<List<BodyMetric>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(analyticsRepositoryProvider).bodyMetrics();
  }

  Future<void> _logWeight() async {
    final unit = ref.read(weightUnitProvider);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log body weight'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Weight (${unit.label})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref.read(analyticsRepositoryProvider).logBodyMetric(value: unit.toKg(value));
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _logWeight,
            icon: const Icon(Icons.add),
            label: const Text('Log weight'),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<BodyMetric>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              final metrics = snapshot.data ?? [];
              if (metrics.isEmpty) {
                return const _EmptyChartHint(message: 'Log your body weight to start tracking it.');
              }
              final points = metrics
                  .map((m) => ProgressPoint(day: m.recordedAt, totalVolume: 0, maxWeight: m.value, setCount: 0))
                  .toList();
              final unit = ref.watch(weightUnitProvider);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ProgressChart(
                  points: points,
                  valueOf: (p) => unit.fromKg(p.maxWeight),
                  label: 'Body weight (${unit.label})',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyChartHint extends StatelessWidget {
  const _EmptyChartHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
