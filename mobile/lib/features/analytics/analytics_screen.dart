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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Volume'),
            Tab(text: 'By exercise'),
            Tab(text: 'Records'),
            Tab(text: 'Measurements'),
          ]),
        ),
        body: const TabBarView(children: [
          _VolumeTrendTab(),
          _ExerciseProgressTab(),
          _RecordsTab(),
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

enum _ProgressMetric { heaviest, volume, reps }

class _ExerciseProgressTabState extends ConsumerState<_ExerciseProgressTab> {
  Exercise? _selected;
  Future<List<ProgressPoint>>? _future;
  Future<PlateauStatus>? _plateauFuture;
  _ProgressMetric _metric = _ProgressMetric.heaviest;

  Future<void> _pickExercise() async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null) return;
    setState(() {
      _selected = exercise;
      // Bodyweight exercises log added load (often 0), so reps is the
      // meaningful progress signal there.
      _metric = exercise.isBodyweight ? _ProgressMetric.reps : _ProgressMetric.heaviest;
      _future = ref.read(analyticsRepositoryProvider).progressOverTime(exerciseId: exercise.id, days: 90);
      _plateauFuture = ref.read(workoutRepositoryProvider).plateauStatus(exercise.id);
    });
  }

  ({double Function(ProgressPoint) valueOf, String label}) _metricConfig(WeightUnit unit) {
    switch (_metric) {
      case _ProgressMetric.heaviest:
        return (valueOf: (p) => unit.fromKg(p.maxWeight), label: 'Heaviest weight (${unit.label})');
      case _ProgressMetric.volume:
        return (valueOf: (p) => unit.fromKg(p.totalVolume), label: 'Volume (${unit.label})');
      case _ProgressMetric.reps:
        return (valueOf: (p) => p.maxReps.toDouble(), label: 'Best set reps');
    }
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
                    final config = _metricConfig(unit);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          SegmentedButton<_ProgressMetric>(
                            segments: const [
                              ButtonSegment(value: _ProgressMetric.heaviest, label: Text('Weight')),
                              ButtonSegment(value: _ProgressMetric.reps, label: Text('Reps')),
                              ButtonSegment(value: _ProgressMetric.volume, label: Text('Volume')),
                            ],
                            selected: {_metric},
                            onSelectionChanged: (s) => setState(() => _metric = s.first),
                            showSelectedIcon: false,
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ProgressChart(
                              points: points,
                              valueOf: config.valueOf,
                              label: config.label,
                            ),
                          ),
                        ],
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
  // Session-local display preference for circumference measurements; the
  // stored value is always cm.
  bool _useInches = false;

  static const _cmPerInch = 2.54;
  double _toStored(double entered) => _useInches ? entered * _cmPerInch : entered;
  double _fromStored(double cm) => _useInches ? cm / _cmPerInch : cm;
  String get _lengthLabel => _useInches ? 'in' : 'cm';

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
    final unitLabel = _selected.isWeight ? weightUnit.label : _lengthLabel;
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
    final stored = _selected.isWeight ? weightUnit.toKg(value) : _toStored(value);
    if (stored <= 0 || stored > 1000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a realistic ${_selected.label.toLowerCase()} value')),
        );
      }
      return;
    }
    try {
      await ref.read(analyticsRepositoryProvider).logBodyMetric(metricType: _selected.metricType, value: stored);
      setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not log ${_selected.label.toLowerCase()}: $e')));
      }
    }
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
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _logMeasurement,
                  icon: const Icon(Icons.add),
                  label: Text('Log ${_selected.label.toLowerCase()}'),
                ),
              ),
              if (!_selected.isWeight) ...[
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('cm')),
                    ButtonSegment(value: true, label: Text('in')),
                  ],
                  selected: {_useInches},
                  onSelectionChanged: (s) => setState(() => _useInches = s.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ],
            ],
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
              final unitLabel = _selected.isWeight ? weightUnit.label : _lengthLabel;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ProgressChart(
                  points: points,
                  valueOf: (p) => _selected.isWeight ? weightUnit.fromKg(p.maxWeight) : _fromStored(p.maxWeight),
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

/// All-time personal records, grouped by exercise — so a PR that scrolled
/// off the active-workout banner isn't lost.
class _RecordsTab extends ConsumerStatefulWidget {
  const _RecordsTab();

  @override
  ConsumerState<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends ConsumerState<_RecordsTab> {
  late Future<List<PersonalRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(workoutRepositoryProvider).personalRecords();
  }

  String _formatValue(PersonalRecord r, WeightUnit unit) {
    if (r.recordType == 'max_reps') return '${r.value.toStringAsFixed(0)} reps';
    final v = unit.fromKg(r.value);
    final n = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
    return '$n ${unit.label}';
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};
    return FutureBuilder<List<PersonalRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return const _EmptyChartHint(message: 'Log some working sets and your personal records will show up here.');
        }
        final byExercise = <String, List<PersonalRecord>>{};
        for (final r in records) {
          byExercise.putIfAbsent(r.exerciseId, () => []).add(r);
        }
        final entries = byExercise.entries.toList()
          ..sort((a, b) => (catalog[a.key]?.name ?? '').compareTo(catalog[b.key]?.name ?? ''));
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final entry in entries)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(catalog[entry.key]?.name ?? 'Exercise',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      for (final r in entry.value)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text(recordTypeLabels[r.recordType] ?? r.recordType)),
                              Text(_formatValue(r, unit), style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (r.achievedAt != null) ...[
                                const SizedBox(width: 10),
                                Text(
                                  '${r.achievedAt!.year}-${r.achievedAt!.month.toString().padLeft(2, '0')}-${r.achievedAt!.day.toString().padLeft(2, '0')}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
