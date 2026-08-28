import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/theme/app_typography.dart';
import '../../core/units/weight_unit.dart';

/// Standard plate denominations available at most commercial gyms.
const _kgPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const _lbPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

/// Common barbell weights, offered as quick-pick chips.
const _kgBars = [20.0, 15.0, 10.0];
const _lbBars = [45.0, 35.0, 25.0];

/// Per-denomination look: bar height (taller = heavier plate) and colour,
/// loosely following competition plate colours so the stack reads at a
/// glance.
(double, Color) _plateLook(double plate, WeightUnit unit) {
  if (unit == WeightUnit.kg) {
    return switch (plate) {
      25.0 => (72, const Color(0xFFD32F2F)),
      20.0 => (66, const Color(0xFF1976D2)),
      15.0 => (58, const Color(0xFFF9A825)),
      10.0 => (50, const Color(0xFF388E3C)),
      5.0 => (40, const Color(0xFF90A4AE)),
      2.5 => (32, const Color(0xFF546E7A)),
      _ => (26, const Color(0xFF8D6E63)),
    };
  }
  return switch (plate) {
    45.0 => (70, const Color(0xFF1976D2)),
    35.0 => (60, const Color(0xFFF9A825)),
    25.0 => (52, const Color(0xFF388E3C)),
    10.0 => (42, const Color(0xFF90A4AE)),
    5.0 => (32, const Color(0xFF546E7A)),
    _ => (26, const Color(0xFF8D6E63)),
  };
}

const _storage = FlutterSecureStorage();
const _barKeyKg = 'plate_calc_bar_kg';
const _barKeyLb = 'plate_calc_bar_lb';

String _num(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// Computes which plates go on each side of the bar to hit [targetWeight],
/// given a [barWeight] (both in the same unit). Returns plates in
/// descending order — what you'd actually load, biggest against the collar.
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

/// Shows the plate calculator for [targetWeight] (already in the caller's
/// display unit). Purely a logging convenience — no workout data is touched.
Future<void> showPlateCalculatorDialog(
  BuildContext context, {
  required double targetWeight,
  required WeightUnit unit,
}) {
  return showDialog(
    context: context,
    builder: (_) => _PlateCalculatorDialog(targetWeight: targetWeight, unit: unit),
  );
}

class _PlateCalculatorDialog extends StatefulWidget {
  const _PlateCalculatorDialog({required this.targetWeight, required this.unit});

  final double targetWeight;
  final WeightUnit unit;

  @override
  State<_PlateCalculatorDialog> createState() => _PlateCalculatorDialogState();
}

class _PlateCalculatorDialogState extends State<_PlateCalculatorDialog> {
  late final TextEditingController _barController;
  double get _defaultBar => widget.unit == WeightUnit.kg ? 20.0 : 45.0;
  String get _storeKey => widget.unit == WeightUnit.kg ? _barKeyKg : _barKeyLb;

  @override
  void initState() {
    super.initState();
    _barController = TextEditingController(text: _num(_defaultBar));
    // Restore the bar the user picked last time — a 15 kg women's bar or a
    // 10 kg technique bar shouldn't have to be re-entered every session.
    _storage.read(key: _storeKey).then((value) {
      final stored = double.tryParse(value ?? '');
      if (stored != null && stored > 0 && mounted) {
        setState(() => _barController.text = _num(stored));
      }
    });
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  void _setBar(double value) {
    setState(() => _barController.text = _num(value));
    _storage.write(key: _storeKey, value: value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final label = unit.label;
    final bar = double.tryParse(_barController.text) ?? _defaultBar;
    final plates = platesPerSide(widget.targetWeight, bar, unit);
    final loaded = bar + 2 * plates.fold<double>(0, (s, p) => s + p);
    final diff = widget.targetWeight - loaded;
    final colorScheme = Theme.of(context).colorScheme;
    final bars = unit == WeightUnit.kg ? _kgBars : _lbBars;

    return AlertDialog(
      title: const Text('Plate calculator'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target: ${_num(widget.targetWeight)} $label',
              style: const TextStyle(fontFamily: AppTypography.mono),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _barController,
              style: const TextStyle(fontFamily: AppTypography.mono),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Bar weight ($label)'),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed > 0) _storage.write(key: _storeKey, value: parsed.toString());
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final b in bars)
                  ChoiceChip(
                    label: Text('${_num(b)} $label', style: const TextStyle(fontFamily: AppTypography.mono)),
                    selected: (bar - b).abs() < 0.01,
                    onSelected: (_) => _setBar(b),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (plates.isEmpty)
              Text(
                widget.targetWeight <= bar
                    ? 'Target is at or below the bar weight — no plates needed.'
                    : "Can't be loaded with standard plates.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else ...[
              Center(child: _BarbellDiagram(plates: plates, unit: unit)),
              const SizedBox(height: 12),
              Text(
                'Per side:  ${plates.map(_num).join('  ·  ')}  $label',
                style: const TextStyle(fontFamily: AppTypography.mono),
              ),
              const SizedBox(height: 4),
              Text(
                diff.abs() < 0.01
                    ? 'Loads to exactly ${_num(loaded)} $label'
                    : 'Loads to ${_num(loaded)} $label  (${_num(diff.abs())} $label ${diff > 0 ? 'short' : 'over'})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: diff.abs() < 0.01 ? colorScheme.onSurfaceVariant : colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// A little barbell: plates mirrored on both sides of a centre bar, biggest
/// against the collar. Heavier plates are drawn taller.
class _BarbellDiagram extends StatelessWidget {
  const _BarbellDiagram({required this.plates, required this.unit});

  /// One side, biggest-first (collar → outer).
  final List<double> plates;
  final WeightUnit unit;

  Widget _plate(double p) {
    final (height, color) = _plateLook(p, unit);
    return Container(
      width: 12,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const maxH = 72.0;
    final sleeve = Container(width: 26, height: 6, color: const Color(0xFFB0BEC5));
    final collar = Container(
      width: 5,
      height: 26,
      decoration: BoxDecoration(color: const Color(0xFF607D8B), borderRadius: BorderRadius.circular(2)),
    );

    return SizedBox(
      height: maxH + 4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          sleeve,
          // left side: smallest outer → biggest against the collar
          for (final p in plates.reversed) _plate(p),
          collar,
          Container(width: 34, height: 8, color: const Color(0xFF90A4AE)),
          collar,
          // right side: biggest against the collar → smallest outer
          for (final p in plates) _plate(p),
          sleeve,
        ],
      ),
    );
  }
}
