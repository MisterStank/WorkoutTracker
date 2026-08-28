import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/units/weight_unit.dart';
import '../../core/widgets/semantic_banner.dart';
import 'exercise_category_icon.dart';
import 'exercise_detail_sheet.dart';
import 'plate_calculator.dart';
import 'set_input_validation.dart';
import 'workout_models.dart';

class LoggedSetInput {
  const LoggedSetInput({required this.reps, required this.weightKg, this.rpe, this.setType = SetType.normal});

  final int reps;
  final double weightKg;
  final double? rpe;
  final SetType setType;
}

/// Bottom sheet for entering reps/weight/RPE/set-type once an exercise has
/// been picked. If [lastSet] is given (the user's most recent set for this
/// exercise), the form pre-fills with those values — the single biggest
/// speed win for logging sets back-to-back in the gym. If [editing] is
/// given instead, the form pre-fills with that set's own values and the
/// sheet becomes a correction ("Save changes") rather than a new log entry
/// — [lastSet]/[suggestion] are ignored when editing. Pops with a
/// LoggedSetInput, or null if cancelled.
Future<LoggedSetInput?> showLogSetSheet(
  BuildContext context,
  Exercise exercise, {
  WorkoutSet? lastSet,
  WorkoutSet? editing,
  required WeightUnit unit,
  ProgressionSuggestion? suggestion,
}) {
  final repsController = TextEditingController(
    text: editing != null
        ? '${editing.reps}'
        : suggestion != null
            ? '${suggestion.suggestedReps}'
            : lastSet == null
                ? ''
                : '${lastSet.reps}',
  );
  final weightController = TextEditingController(
    text: editing != null
        ? _formatWeight(unit.fromKg(editing.weightKg))
        : suggestion != null
            ? _formatWeight(unit.fromKg(suggestion.suggestedWeightKg))
            : lastSet == null
                ? ''
                : _formatWeight(unit.fromKg(lastSet.weightKg)),
  );
  final rpeController = TextEditingController(text: editing?.rpe == null ? '' : '${editing!.rpe}');
  final formKey = GlobalKey<FormState>();
  SetType setType = editing?.setType ?? SetType.normal;

  return showModalBottomSheet<LoggedSetInput>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return StatefulBuilder(builder: (context, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => showExerciseDetailSheet(context, exercise),
                      child: ExerciseCategoryIcon(category: exercise.category),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(exercise.name, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calculate_outlined),
                      tooltip: 'Plate calculator',
                      onPressed: () {
                        final target = double.tryParse(weightController.text);
                        showPlateCalculatorDialog(context, targetWeight: target ?? 0, unit: unit);
                      },
                    ),
                  ],
                ),
                if (editing == null && lastSet != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last time: ${lastSet.reps} × ${_formatWeight(unit.fromKg(lastSet.weightKg))} ${unit.label}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: AppTypography.mono, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                if (editing == null && suggestion != null) ...[
                  const SizedBox(height: 8),
                  SemanticBanner.info(context, message: suggestion.reasoning, icon: Icons.auto_graph),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: repsController,
                        style: const TextStyle(fontFamily: AppTypography.mono),
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Reps', prefixIcon: Icon(Icons.repeat)),
                        validator: validateReps,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: weightController,
                        style: const TextStyle(fontFamily: AppTypography.mono),
                        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: exercise.isBodyweight),
                        decoration: InputDecoration(
                          labelText: exercise.isBodyweight ? 'Added wt (${unit.label})' : 'Weight (${unit.label})',
                          prefixIcon: const Icon(Icons.scale),
                        ),
                        validator: (v) => validateWeight(
                          v,
                          maxWeightInUnit: unit.fromKg(maxWeightKg),
                          allowNonPositive: exercise.isBodyweight,
                        ),
                      ),
                    ),
                  ],
                ),
                if (exercise.isBodyweight)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '0 = bodyweight · negative = assisted',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: rpeController,
                  style: const TextStyle(fontFamily: AppTypography.mono),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'RPE (optional)', prefixIcon: Icon(Icons.speed)),
                  validator: validateRpe,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Set type', style: Theme.of(context).textTheme.labelLarge),
                ),
                const SizedBox(height: 8),
                SegmentedButton<SetType>(
                  segments: const [
                    ButtonSegment(value: SetType.normal, label: Text('Normal')),
                    ButtonSegment(value: SetType.warmup, label: Text('Warm-up')),
                    ButtonSegment(value: SetType.dropset, label: Text('Drop')),
                    ButtonSegment(value: SetType.failure, label: Text('Failure')),
                  ],
                  selected: {setType},
                  onSelectionChanged: (selection) => setSheetState(() => setType = selection.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                if (setType == SetType.warmup)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      "Won't count toward PRs or volume",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.of(context).pop(LoggedSetInput(
                      reps: int.parse(repsController.text),
                      weightKg: unit.toKg(double.parse(weightController.text)),
                      rpe: rpeController.text.isEmpty ? null : double.tryParse(rpeController.text),
                      setType: setType,
                    ));
                  },
                  icon: const Icon(Icons.check),
                  label: Text(editing == null ? 'Log set' : 'Save changes'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}

/// Whole numbers show with no decimals; fractional weights keep up to two
/// places with trailing zeros trimmed (so a 2.5 kg-rounded suggestion like
/// 67.5 stays "67.5", and a hand-logged 66.25 stays "66.25" rather than
/// being mangled to "66.3").
String _formatWeight(double value) {
  if (value.truncateToDouble() == value) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
