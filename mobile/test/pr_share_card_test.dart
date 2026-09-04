import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/core/units/weight_unit.dart';
import 'package:gymon/features/sharing/pr_share_card.dart';
import 'package:gymon/features/workout/workout_models.dart';

PersonalRecord _record(String recordType, double value) =>
    PersonalRecord(exerciseId: 'bench', recordType: recordType, value: value);

// The card has a fixed 340x340 size and uses Spacer(), so it needs a surface
// at least that big and a bounded box (not a scroll view).
Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.binding.setSurfaceSize(const Size(600, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: card))));
}

void main() {
  group('PrShareCard', () {
    testWidgets('shows a weight record with the unit label, converting from kg', (tester) async {
      await _pump(tester, PrShareCard(
        exerciseName: 'Bench Press',
        records: [_record('max_weight', 100)],
        unit: WeightUnit.kg,
      ));

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('100 kg'), findsOneWidget);
      expect(find.text('heaviest weight'), findsOneWidget);
    });

    testWidgets('converts a weight record to pounds', (tester) async {
      await _pump(tester, PrShareCard(
        exerciseName: 'Bench Press',
        records: [_record('max_weight', 100)],
        unit: WeightUnit.lb,
      ));

      expect(find.textContaining('lb'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('a "most reps" record is shown as a plain count, never as kg/lb', (tester) async {
      await _pump(tester, PrShareCard(
        exerciseName: 'Pull-Up',
        records: [_record('max_reps', 12)],
        unit: WeightUnit.kg,
      ));

      expect(find.text('12 reps'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.text('most reps'), findsOneWidget);
    });

    testWidgets('a "most reps" record is unaffected by the pounds setting', (tester) async {
      await _pump(tester, PrShareCard(
        exerciseName: 'Pull-Up',
        records: [_record('max_reps', 12)],
        unit: WeightUnit.lb,
      ));

      expect(find.text('12 reps'), findsOneWidget);
      expect(find.textContaining('lb'), findsNothing);
    });
  });
}
