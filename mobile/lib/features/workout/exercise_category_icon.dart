import 'package:flutter/material.dart';

/// A small hand-drawn vector glyph per exercise category (push/pull/legs/
/// arms/core) — not a photo or AI-generated image, just flat geometric
/// shapes via CustomPainter, so every exercise has *some* visual identity
/// even though the catalog has no real exercise media yet.
class ExerciseCategoryIcon extends StatelessWidget {
  const ExerciseCategoryIcon({super.key, required this.category, this.size = 40});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      padding: EdgeInsets.all(size * 0.22),
      child: CustomPaint(painter: _CategoryPainter(category: category, color: scheme.onPrimaryContainer)),
    );
  }
}

class _CategoryPainter extends CustomPainter {
  _CategoryPainter({required this.category, required this.color});

  final String category;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    final w = size.width;
    final h = size.height;

    switch (category) {
      case 'push':
        // A barbell resting over a flat bench line — the universal "press" glyph.
        canvas.drawLine(Offset(0, h * 0.35), Offset(w, h * 0.35), stroke);
        canvas.drawCircle(Offset(w * 0.12, h * 0.35), h * 0.16, fill);
        canvas.drawCircle(Offset(w * 0.88, h * 0.35), h * 0.16, fill);
        canvas.drawLine(Offset(w * 0.2, h * 0.75), Offset(w * 0.8, h * 0.75), stroke);
        break;
      case 'pull':
        // A downward V — pulling something toward the body.
        final path = Path()
          ..moveTo(0, h * 0.1)
          ..lineTo(w * 0.5, h * 0.85)
          ..lineTo(w, h * 0.1);
        canvas.drawPath(path, stroke);
        break;
      case 'legs':
        // A bent-knee leg silhouette — squat/lunge glyph.
        final path = Path()
          ..moveTo(w * 0.3, 0)
          ..lineTo(w * 0.3, h * 0.5)
          ..lineTo(w * 0.75, h * 0.75)
          ..moveTo(w * 0.3, h * 0.5)
          ..lineTo(w * 0.15, h);
        canvas.drawPath(path, stroke);
        break;
      case 'arms':
        // A flexed-bicep arc.
        final rect = Rect.fromLTWH(w * 0.05, h * 0.05, w * 0.9, h * 1.3);
        canvas.drawArc(rect, 3.4, 2.2, false, stroke);
        canvas.drawCircle(Offset(w * 0.82, h * 0.28), h * 0.14, fill);
        break;
      case 'core':
      default:
        // A segmented torso — three stacked rounded bars.
        for (var i = 0; i < 3; i++) {
          final top = h * (0.08 + i * 0.34);
          final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.15, top, w * 0.7, h * 0.2),
            Radius.circular(h * 0.08),
          );
          canvas.drawRRect(r, fill);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryPainter oldDelegate) =>
      oldDelegate.category != category || oldDelegate.color != color;
}
