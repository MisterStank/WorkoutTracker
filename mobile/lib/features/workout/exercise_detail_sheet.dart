import 'package:flutter/material.dart';

import 'exercise_category_icon.dart';
import 'workout_models.dart';

/// Tapping an exercise's category icon (in the picker or the log-set sheet)
/// opens this instead of immediately selecting it — the "what is this
/// exercise, how do I do it" answer the app didn't have before.
Future<void> showExerciseDetailSheet(BuildContext context, Exercise exercise) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExerciseCategoryIcon(category: exercise.category, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        exercise.category[0].toUpperCase() + exercise.category.substring(1),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              exercise.instructions.isEmpty ? 'No instructions written for this exercise yet.' : exercise.instructions,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}
