import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/units/weight_unit.dart';

/// Standard plate denominations available at most commercial gyms.
const _kgPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const _lbPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

/// Computes which plates go on each side of the bar to hit [targetWeight],
/// given a [barWeight] (both in the same unit). Returns plates in
/// descending order — what you'd actually load on, biggest first.
List<double> platesPerSide(double targetWeight, double barWeight, WeightUnit unit) {
  final perSide = (targetWeight - barWeight) / 2;
  if (perSide <= 0) return const [];

  final denominations = unit == WeightUnit.kg ? _kgPlates : _lbPlates;
  var remaining = perSide;
  final plates = <double>[];
  for (final plate in denominations) {
    while (remaining + 1e-9 >= plate) {
      plates.add(plate);
      remaining -= plate;
    }
  }
  return plates;
}

/// Shows a dialog with the plate breakdown for [targetWeight] (already in
/// the caller's display unit). Purely a logging convenience — no data is
/// read or written.
Future<void> showPlateCalculatorDialog(BuildContext context, {required double targetWeight, required WeightUnit unit}) {
  final defaultBar = unit == WeightUnit.kg ? 20.0 : 45.0;
  final barController = TextEditingController(text: defaultBar.toStringAsFixed(0));

  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final bar = double.tryParse(barController.text) ?? defaultBar;
      final plates = platesPerSide(targetWeight, bar, unit);

      return AlertDialog(
        title: const Text('Plate calculator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target: ${targetWeight.toStringAsFixed(1)} ${unit.label}', style: const TextStyle(fontFamily: AppTypography.mono)),
            const SizedBox(height: 12),
            TextField(
              controller: barController,
              style: const TextStyle(fontFamily: AppTypography.mono),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Bar weight (${unit.label})'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (plates.isEmpty)
              Text(
                targetWeight <= bar ? 'Target is at or below the bar weight.' : "Can't be made with standard plates.",
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else ...[
              Text('Per side:', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: plates
                    .map((p) => Chip(label: Text(p == p.truncate() ? '${p.toInt()}' : '$p', style: const TextStyle(fontFamily: AppTypography.mono))))
                    .toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      );
    }),
  );
}
