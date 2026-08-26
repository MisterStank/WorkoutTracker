import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/workout/exercise_detail_sheet.dart';
import 'package:mobile/features/workout/workout_models.dart';

void main() {
  testWidgets('shows the exercise name, category, and written instructions', (tester) async {
    const exercise = Exercise(
      id: 'ex1',
      name: 'Barbell Back Squat',
      category: 'legs',
      instructions: 'Bar rests on your upper traps. Sit back until thighs are at least parallel, then stand.',
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showExerciseDetailSheet(context, exercise),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.textContaining('Bar rests on your upper traps'), findsOneWidget);
  });

  testWidgets('shows a fallback message when an exercise has no written instructions', (tester) async {
    const exercise = Exercise(id: 'ex2', name: 'Custom Move', category: 'core');

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showExerciseDetailSheet(context, exercise),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('No instructions written for this exercise yet.'), findsOneWidget);
  });
}
