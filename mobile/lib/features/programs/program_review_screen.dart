import 'package:flutter/material.dart';

import 'fitness_profile_models.dart';

/// Read-only view of a just-generated Program — generation already
/// persisted every day as an ordinary WorkoutTemplate, so this screen is a
/// confirmation/summary, not a second save step. Each day is a card the
/// user can glance at; starting a workout from one happens the normal way,
/// from the Templates tab, since a program day is just a template.
class ProgramReviewScreen extends StatelessWidget {
  const ProgramReviewScreen({super.key, required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(program.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${program.daysPerWeek} days a week · ${program.goal.label}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Saved as ${program.days.length} template${program.days.length == 1 ? '' : 's'} — start any day from the Templates tab whenever you train it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (program.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(program.notes, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 16),
          ...program.days.map((day) => _ProgramDayCard(day: day)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _ProgramDayCard extends StatelessWidget {
  const _ProgramDayCard({required this.day});

  final ProgramDay day;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day.dayLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (day.template.exercises.isEmpty)
              Text(
                'No matching exercises for this day — try widening your equipment or exclusions.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              Text(
                '${day.template.exercises.length} exercise${day.template.exercises.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
