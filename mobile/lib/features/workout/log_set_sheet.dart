import 'package:flutter/material.dart';

import 'workout_models.dart';

class LoggedSetInput {
  const LoggedSetInput({required this.reps, required this.weightKg, this.rpe});

  final int reps;
  final double weightKg;
  final double? rpe;
}

/// Bottom sheet for entering reps/weight/RPE once an exercise has been
/// picked. Pops with a LoggedSetInput, or null if cancelled.
Future<LoggedSetInput?> showLogSetSheet(BuildContext context, Exercise exercise) {
  final repsController = TextEditingController();
  final weightController = TextEditingController();
  final rpeController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showModalBottomSheet<LoggedSetInput>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
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
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.fitness_center, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(exercise.name, style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: repsController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Reps', prefixIcon: Icon(Icons.repeat)),
                      validator: (v) => int.tryParse(v ?? '') == null ? 'Whole number' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Weight (kg)', prefixIcon: Icon(Icons.scale)),
                      validator: (v) => double.tryParse(v ?? '') == null ? 'Number' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rpeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'RPE (optional)', prefixIcon: Icon(Icons.speed)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(LoggedSetInput(
                    reps: int.parse(repsController.text),
                    weightKg: double.parse(weightController.text),
                    rpe: rpeController.text.isEmpty ? null : double.tryParse(rpeController.text),
                  ));
                },
                icon: const Icon(Icons.check),
                label: const Text('Log set'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
