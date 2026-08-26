import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/units/weight_unit.dart';
import 'package:mobile/features/sharing/workout_summary_share_card.dart';
import 'package:mobile/features/workout/workout_models.dart';

Exercise _exercise(String id, String name) => Exercise(id: id, name: name, category: 'push');

WorkoutSet _set(String id, {required String exerciseId, required int setNumber, required int reps, required double weightKg, SetType setType = SetType.normal}) {
  return WorkoutSet(id: id, exerciseId: exerciseId, setNumber: setNumber, reps: reps, weightKg: weightKg, setType: setType);
}

PersonalRecord _record(String exerciseId) => PersonalRecord(exerciseId: exerciseId, recordType: 'max_weight', value: 80);

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));
}

void main() {
  group('WorkoutSummaryShareCard', () {
    testWidgets('lists every working set per exercise, not just the best one', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1, 10),
        endedAt: DateTime(2026, 1, 1, 10, 45),
        status: 'COMPLETED',
        notes: '',
        sets: [
          _set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60),
          _set('s2', exerciseId: 'bench', setNumber: 2, reps: 5, weightKg: 80),
          _set('s3', exerciseId: 'row', setNumber: 1, reps: 10, weightKg: 40),
        ],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press'), 'row': _exercise('row', 'Barbell Row')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Barbell Row'), findsOneWidget);
      expect(find.text('8 × 60 kg'), findsOneWidget, reason: 'both bench sets should be listed, not just the heavier one');
      expect(find.text('5 × 80 kg'), findsOneWidget);
      expect(find.text('10 × 40 kg'), findsOneWidget);
    });

    testWidgets('shows who did it and when', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 6, 10), // a Tuesday
        endedAt: DateTime(2026, 1, 6, 10, 30),
        status: 'COMPLETED',
        notes: '',
        sets: [_set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60)],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg, displayName: 'Jamie Lee'));

      expect(find.textContaining('Jamie Lee'), findsOneWidget);
      expect(find.textContaining('Tue 1/6'), findsOneWidget);
    });

    testWidgets('omits the name line entirely when no display name is given', (tester) async {
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 6), endedAt: DateTime(2026, 1, 6, 0, 30), status: 'COMPLETED', notes: '', sets: [
        _set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60),
      ]);
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      // The date-only line should just be the date, no leading " · " artifact.
      expect(find.text('Tue 1/6'), findsOneWidget);
    });

    testWidgets('uses the given title as the headline instead of the weekday fallback', (tester) async {
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 6), endedAt: DateTime(2026, 1, 6, 0, 30), status: 'COMPLETED', notes: '', sets: [
        _set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60),
      ]);
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg, title: 'Upper 1'));

      expect(find.text('Upper 1'), findsOneWidget);
      expect(find.text('Tuesday Workout'), findsNothing);
    });

    testWidgets('falls back to a weekday-based title when none is given', (tester) async {
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 6), endedAt: DateTime(2026, 1, 6, 0, 30), status: 'COMPLETED', notes: '', sets: [
        _set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60),
      ]);
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('Tuesday Workout'), findsOneWidget);
    });

    testWidgets('flags an exercise with a PR badge when it earned one this session', (tester) async {
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 1), endedAt: DateTime(2026, 1, 1, 0, 30), status: 'COMPLETED', notes: '', sets: [
        _set('s1', exerciseId: 'bench', setNumber: 1, reps: 5, weightKg: 80),
        _set('s2', exerciseId: 'row', setNumber: 1, reps: 10, weightKg: 40),
      ]);
      final catalog = {'bench': _exercise('bench', 'Bench Press'), 'row': _exercise('row', 'Barbell Row')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg, newRecords: [_record('bench')]));

      expect(find.text('PR'), findsOneWidget, reason: 'only the exercise that actually earned a PR should be flagged');
    });

    testWidgets('shows no PR badge when newRecords is empty (e.g. shared later from History)', (tester) async {
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 1), endedAt: DateTime(2026, 1, 1, 0, 30), status: 'COMPLETED', notes: '', sets: [
        _set('s1', exerciseId: 'bench', setNumber: 1, reps: 5, weightKg: 80),
      ]);
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('PR'), findsNothing);
    });

    testWidgets('excludes warm-up sets entirely', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1),
        endedAt: DateTime(2026, 1, 1, 0, 30),
        status: 'COMPLETED',
        notes: '',
        sets: [
          _set('s1', exerciseId: 'bench', setNumber: 1, reps: 10, weightKg: 200, setType: SetType.warmup),
          _set('s2', exerciseId: 'bench', setNumber: 2, reps: 5, weightKg: 80),
        ],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('5 × 80 kg'), findsOneWidget);
      expect(find.textContaining('200'), findsNothing);
    });

    testWidgets('an exercise with only warm-up sets is omitted entirely', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1),
        endedAt: DateTime(2026, 1, 1, 0, 10),
        status: 'COMPLETED',
        notes: '',
        sets: [_set('s1', exerciseId: 'bench', setNumber: 1, reps: 10, weightKg: 20, setType: SetType.warmup)],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('Bench Press'), findsNothing);
    });

    testWidgets('shows an overflow count beyond the first ten exercises', (tester) async {
      final sets = <WorkoutSet>[];
      final catalog = <String, Exercise>{};
      for (var i = 0; i < 12; i++) {
        final id = 'ex$i';
        sets.add(_set('s$i', exerciseId: id, setNumber: 1, reps: 8, weightKg: 40));
        catalog[id] = _exercise(id, 'Exercise $i');
      }
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 1), endedAt: DateTime(2026, 1, 1, 0, 30), status: 'COMPLETED', notes: '', sets: sets);

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('+2 more exercises'), findsOneWidget);
    });

    testWidgets('falls back to "Exercise" for a set whose exercise is missing from the catalog', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1),
        endedAt: DateTime(2026, 1, 1, 0, 10),
        status: 'COMPLETED',
        notes: '',
        sets: [_set('s1', exerciseId: 'unknown', setNumber: 1, reps: 8, weightKg: 40)],
      );

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: const {}, unit: WeightUnit.kg));

      expect(find.text('Exercise'), findsOneWidget);
    });
  });
}
