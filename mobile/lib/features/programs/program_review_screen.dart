import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workout/superset_provider.dart';
import '../workout/workout_provider.dart';
import 'fitness_profile_models.dart';
import 'fitness_profile_provider.dart';
import 'program_targets_provider.dart';

/// A program's detail/action screen — reached by tapping it on the Programs
/// tab. Answers "now what": mark it as the one you're following (drives
/// Home's "Continue" card) and start a workout from any of its days
/// directly, rather than just listing its exercises with nowhere to go.
class ProgramReviewScreen extends ConsumerStatefulWidget {
  const ProgramReviewScreen({super.key, required this.program});

  final Program program;

  @override
  ConsumerState<ProgramReviewScreen> createState() => _ProgramReviewScreenState();
}

class _ProgramReviewScreenState extends ConsumerState<ProgramReviewScreen> {
  late Program _program;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    _program = widget.program;
  }

  Future<void> _useThisProgram() async {
    setState(() => _activating = true);
    try {
      final updated = await ref.read(fitnessProfileRepositoryProvider).setActiveProgram(_program.id);
      if (mounted) {
        setState(() => _program = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Now following ${updated.name} — it's on your Home tab")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not activate program: $e')));
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _startDay(ProgramDay day) async {
    ref.read(activeSupersetsProvider.notifier).reset();
    await ref.read(activeWorkoutProvider.notifier).start(templateId: day.template.id);
    unawaited(ref.read(activeProgramTargetsProvider.notifier).loadForTemplate(day.template.id));
    if (!mounted) return;
    // Return to the app shell (Home tab shows the resume bar / active
    // workout automatically) rather than leaving the user on this
    // now-stale review screen mid-workout.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_program.name)),
      // A clear way out of the flow — reached right after generating a
      // program (on top of the now-stale profile form) or by tapping one
      // on the Programs tab; either way "Done" returns to the app shell
      // rather than making the user hunt for the back arrow, or tap it
      // twice to get past the form.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('Done'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_program.daysPerWeek} days a week · ${_program.goal.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_program.isActive)
                Chip(
                  avatar: const Icon(Icons.check_circle, size: 16),
                  label: const Text('Active'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a day below to start a workout from it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.trending_up, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${_program.progressionRule.label}. ',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: _program.progressionRule.blurb,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ])),
              ),
            ],
          ),
          if (_program.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_program.notes, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 16),
          if (!_program.isActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                onPressed: _activating ? null : _useThisProgram,
                icon: _activating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Use this program'),
              ),
            ),
          ...widget.program.days.map((day) => _ProgramDayCard(day: day, onStart: () => _startDay(day))),
        ],
      ),
    );
  }
}

class _ProgramDayCard extends StatelessWidget {
  const _ProgramDayCard({required this.day, required this.onStart});

  final ProgramDay day;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final empty = day.template.exercises.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.dayLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    empty
                        ? 'No matching exercises for this day — try widening your equipment or exclusions.'
                        : '${day.template.exercises.length} exercise${day.template.exercises.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!empty) ...[
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Start ${day.dayLabel}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
