import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/units/weight_unit.dart';
import 'package:mobile/features/sharing/workout_summary_share_card.dart';
import 'package:mobile/features/workout/workout_models.dart';

Exercise _exercise(String id, String name) => Exercise(id: id, name: name, category: 'push');

WorkoutSet _set(String id, {required String exerciseId, required int setNumber, required int reps, required double weightKg, SetType setType = SetType.normal}) {
  return WorkoutSet(id: id, exerciseId: exerciseId, setNumber: setNumber, reps: reps, weightKg: weightKg, setType: setType);
}

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));
}

void main() {
  group('WorkoutSummaryShareCard', () {
    testWidgets('shows per-exercise set count and best set, not just names', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1, 10),
        endedAt: DateTime(2026, 1, 1, 10, 45),
        status: 'COMPLETED',
        notes: '',
        sets: [
          _set('s1', exerciseId: 'bench', setNumber: 1, reps: 8, weightKg: 60),
          _set('s2', exerciseId: 'bench', setNumber: 2, reps: 5, weightKg: 80), // heavier -> should be "best"
          _set('s3', exerciseId: 'row', setNumber: 1, reps: 10, weightKg: 40),
        ],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press'), 'row': _exercise('row', 'Barbell Row')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Barbell Row'), findsOneWidget);
      expect(find.text('2 sets'), findsOneWidget, reason: 'Bench Press has 2 working sets');
      expect(find.text('1 set'), findsOneWidget, reason: 'Barbell Row has 1 working set, singular label');
      expect(find.text('5 × 80 kg'), findsOneWidget, reason: 'heaviest set (80kg) should win over the lighter 60kg set, not the first-logged one');
    });

    testWidgets('excludes warm-up sets from set counts and best-set selection', (tester) async {
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

      expect(find.text('1 set'), findsOneWidget, reason: 'the 200kg warm-up must not count as a working set');
      expect(find.text('5 × 80 kg'), findsOneWidget, reason: 'the warm-up (heavier, but a warm-up) must not win best-set');
      expect(find.textContaining('200'), findsNothing);
    });

    testWidgets('an exercise with only warm-up sets is omitted entirely', (tester) async {
      final workout = Workout(
        id: 'w1',
        startedAt: DateTime(2026, 1, 1),
        endedAt: DateTime(2026, 1, 1, 0, 10),
        status: 'COMPLETED',
        notes: '',
        sets: [
          _set('s1', exerciseId: 'bench', setNumber: 1, reps: 10, weightKg: 20, setType: SetType.warmup),
        ],
      );
      final catalog = {'bench': _exercise('bench', 'Bench Press')};

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('Bench Press'), findsNothing);
    });

    testWidgets('shows an overflow count beyond the first five exercises', (tester) async {
      final sets = <WorkoutSet>[];
      final catalog = <String, Exercise>{};
      for (var i = 0; i < 7; i++) {
        final id = 'ex$i';
        sets.add(_set('s$i', exerciseId: id, setNumber: 1, reps: 8, weightKg: 40));
        catalog[id] = _exercise(id, 'Exercise $i');
      }
      final workout = Workout(id: 'w1', startedAt: DateTime(2026, 1, 1), endedAt: DateTime(2026, 1, 1, 0, 30), status: 'COMPLETED', notes: '', sets: sets);

      await _pump(tester, WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: WeightUnit.kg));

      expect(find.text('+2 more'), findsOneWidget);
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
