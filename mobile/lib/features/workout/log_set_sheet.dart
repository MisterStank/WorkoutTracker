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
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(exercise.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: repsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reps'),
                validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a whole number' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: rpeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'RPE (optional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.of(context).pop(LoggedSetInput(
                    reps: int.parse(repsController.text),
                    weightKg: double.parse(weightController.text),
                    rpe: rpeController.text.isEmpty ? null : double.tryParse(rpeController.text),
                  ));
                },
                child: const Text('Log set'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
