import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/units_provider.dart';
import '../../core/units/weight_unit.dart';
import '../../core/widgets/semantic_banner.dart';
import '../workout/exercise_picker_screen.dart';
import '../workout/workout_models.dart';
import '../workout/workout_provider.dart';
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
            Tab(text: 'Measurements'),
          ]),
        ),
        body: const TabBarView(children: [
          _VolumeTrendTab(),
          _ExerciseProgressTab(),
          _MeasurementsTab(),
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
  Future<PlateauStatus>? _plateauFuture;

  Future<void> _pickExercise() async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null) return;
    setState(() {
      _selected = exercise;
      _future = ref.read(analyticsRepositoryProvider).progressOverTime(exerciseId: exercise.id, days: 90);
      _plateauFuture = ref.read(workoutRepositoryProvider).plateauStatus(exercise.id);
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
        if (_plateauFuture != null)
          FutureBuilder<PlateauStatus>(
            future: _plateauFuture,
            builder: (context, snapshot) {
              final status = snapshot.data;
              if (status == null || !status.isPlateaued) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SemanticBanner.warning(context, message: status.message),
              );
            },
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

/// A trackable body measurement. Only bodyweight uses the kg/lb preference
/// (`isWeight`) — circumference measurements are logged in cm, matching
/// what a tape measure actually reads, rather than overloading the weight
/// unit toggle for an unrelated quantity.
class MeasurementType {
  const MeasurementType(this.metricType, this.label, {this.isWeight = false});

  final String metricType;
  final String label;
  final bool isWeight;

  String unitLabel(WeightUnit weightUnit) => isWeight ? weightUnit.label : 'cm';
}

const _measurementTypes = [
  MeasurementType('bodyweight_kg', 'Body weight', isWeight: true),
  MeasurementType('waist_cm', 'Waist'),
  MeasurementType('chest_cm', 'Chest'),
  MeasurementType('arm_cm', 'Arms'),
  MeasurementType('thigh_cm', 'Thighs'),
  MeasurementType('hip_cm', 'Hips'),
];

class _MeasurementsTab extends ConsumerStatefulWidget {
  const _MeasurementsTab();

  @override
  ConsumerState<_MeasurementsTab> createState() => _MeasurementsTabState();
}

class _MeasurementsTabState extends ConsumerState<_MeasurementsTab> {
  MeasurementType _selected = _measurementTypes.first;
  Future<List<BodyMetric>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(analyticsRepositoryProvider).bodyMetrics(metricType: _selected.metricType);
  }

  Future<void> _logMeasurement() async {
    final weightUnit = ref.read(weightUnitProvider);
    final unitLabel = _selected.unitLabel(weightUnit);
    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log ${_selected.label.toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '${_selected.label} ($unitLabel)'),
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
    final stored = _selected.isWeight ? weightUnit.toKg(value) : value;
    await ref.read(analyticsRepositoryProvider).logBodyMetric(metricType: _selected.metricType, value: stored);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final weightUnit = ref.watch(weightUnitProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<MeasurementType>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Measurement', isDense: true),
            items: _measurementTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (t) {
              if (t == null) return;
              setState(() {
                _selected = t;
                _reload();
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: FilledButton.icon(
            onPressed: _logMeasurement,
            icon: const Icon(Icons.add),
            label: Text('Log ${_selected.label.toLowerCase()}'),
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
                return _EmptyChartHint(message: 'Log your ${_selected.label.toLowerCase()} to start tracking it.');
              }
              final points = metrics
                  .map((m) => ProgressPoint(day: m.recordedAt, totalVolume: 0, maxWeight: m.value, setCount: 0))
                  .toList();
              final unitLabel = _selected.unitLabel(weightUnit);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ProgressChart(
                  points: points,
                  valueOf: (p) => _selected.isWeight ? weightUnit.fromKg(p.maxWeight) : p.maxWeight,
                  label: '${_selected.label} ($unitLabel)',
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
            Icon(Icons.show_chart, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
