import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import 'analytics_models.dart';

/// A line chart over a list of ProgressPoints, plotting whatever
/// [valueOf] extracts (max weight, total volume, body weight, ...) against
/// day-of-range on the x-axis.
class ProgressChart extends StatelessWidget {
  const ProgressChart({super.key, required this.points, required this.valueOf, required this.label});

  final List<ProgressPoint> points;
  final double Function(ProgressPoint) valueOf;
  final String label;

  @override
  Widget build(BuildContext context) {
    final firstDay = points.first.day;
    final spots = points
        .map((p) => FlSpot(p.day.difference(firstDay).inDays.toDouble(), valueOf(p)))
        .toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final yPadding = (maxY - minY) * 0.15 + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: (minY - yPadding).clamp(0, double.infinity),
              maxY: maxY + yPadding,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final day = firstDay.add(Duration(days: value.round()));
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${day.month}/${day.day}', style: const TextStyle(fontFamily: AppTypography.mono, fontSize: 10)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Theme.of(context).colorScheme.inverseSurface,
                  getTooltipItems: (touchedSpots) => touchedSpots
                      .map((s) => LineTooltipItem(s.y.toStringAsFixed(1), TextStyle(fontFamily: AppTypography.mono, color: Theme.of(context).colorScheme.onInverseSurface)))
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 3,
                  dotData: FlDotData(show: spots.length <= 30),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
