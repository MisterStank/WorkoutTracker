import 'package:flutter/material.dart';

import 'pet_models.dart';

/// Placeholder pet art for v1: a layered vector blob drawn from the pet's
/// appearance keys — body shape by species + stage, colour by tint,
/// expression by mood, plus a dot per equipped accessory. The server returns
/// asset *keys* (not images), so swapping in real illustration later is a
/// content drop with no change here beyond this widget.
class PetAvatar extends StatelessWidget {
  const PetAvatar({super.key, required this.pet, this.size = 160});

  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PetPainter(
          species: pet.species,
          stage: pet.stage,
          color: _tintColor(pet.color),
          mood: pet.moodState,
          accessoryCount: pet.appearance.layers.length,
        ),
      ),
    );
  }
}

Color _tintColor(PetColor c) {
  switch (c) {
    case PetColor.green:
      return const Color(0xFF4CAF7D);
    case PetColor.red:
      return const Color(0xFFE0574B);
    case PetColor.blue:
      return const Color(0xFF4C8DE0);
    case PetColor.amber:
      return const Color(0xFFE0A94C);
    case PetColor.violet:
      return const Color(0xFF9B6BE0);
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({
    required this.species,
    required this.stage,
    required this.color,
    required this.mood,
    required this.accessoryCount,
  });

  final PetSpecies species;
  final PetStage stage;
  final Color color;
  final MoodState mood;
  final int accessoryCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Body grows with stage: egg small, champion fills the frame.
    final scale = 0.45 + 0.13 * stage.index;
    final bodyR = size.shortestSide / 2 * scale;

    // Neglected pets look deflated + desaturated.
    final bodyColor = mood == MoodState.neglected ? Color.alphaBlend(Colors.grey.withValues(alpha: 0.45), color) : color;

    final bodyPaint = Paint()..color = bodyColor;
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.08);
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, bodyR * 0.9), width: bodyR * 1.8, height: bodyR * 0.5),
      shadowPaint,
    );

    switch (species) {
      case PetSpecies.sprout:
        canvas.drawCircle(center, bodyR, bodyPaint);
        _leaf(canvas, center.translate(0, -bodyR), bodyR * 0.5, bodyColor);
      case PetSpecies.ember:
        _teardrop(canvas, center, bodyR, bodyPaint);
      case PetSpecies.pebble:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: bodyR * 2, height: bodyR * 1.7),
            Radius.circular(bodyR * 0.6),
          ),
          bodyPaint,
        );
      case PetSpecies.drift:
        canvas.drawOval(
          Rect.fromCenter(center: center, width: bodyR * 2.1, height: bodyR * 1.6),
          bodyPaint,
        );
    }

    if (stage == PetStage.egg) {
      // An egg has no face — draw a couple of shell cracks instead.
      final crack = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center.translate(-bodyR * 0.4, -bodyR * 0.2), center.translate(-bodyR * 0.1, bodyR * 0.1), crack);
      canvas.drawLine(center.translate(-bodyR * 0.1, bodyR * 0.1), center.translate(bodyR * 0.3, -bodyR * 0.1), crack);
    } else {
      _face(canvas, center, bodyR, mood);
    }

    // Equipped accessories: a little row of dots above the head.
    if (accessoryCount > 0) {
      final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
      for (var i = 0; i < accessoryCount && i < 5; i++) {
        canvas.drawCircle(center.translate((i - accessoryCount / 2) * 10 + 5, -bodyR - 12), 3, dotPaint);
      }
    }
  }

  void _face(Canvas canvas, Offset center, double bodyR, MoodState mood) {
    final eyePaint = Paint()..color = Colors.black87;
    final eyeDx = bodyR * 0.35;
    final eyeDy = -bodyR * 0.1;
    final eyeR = bodyR * 0.09;

    if (mood == MoodState.neglected) {
      // Closed, sad eyes: short downward strokes.
      final s = Paint()
        ..color = Colors.black87
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center.translate(-eyeDx - 4, eyeDy - 3), center.translate(-eyeDx + 4, eyeDy + 3), s);
      canvas.drawLine(center.translate(eyeDx - 4, eyeDy + 3), center.translate(eyeDx + 4, eyeDy - 3), s);
    } else {
      canvas.drawCircle(center.translate(-eyeDx, eyeDy), eyeR, eyePaint);
      canvas.drawCircle(center.translate(eyeDx, eyeDy), eyeR, eyePaint);
    }

    final mouth = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final mouthRect = Rect.fromCenter(center: center.translate(0, bodyR * 0.28), width: bodyR * 0.6, height: bodyR * 0.4);
    switch (mood) {
      case MoodState.happy:
        canvas.drawArc(mouthRect, 0.2, 2.7, false, mouth);
      case MoodState.content:
        canvas.drawLine(mouthRect.centerLeft, mouthRect.centerRight, mouth);
      case MoodState.low:
      case MoodState.neglected:
        canvas.drawArc(mouthRect.translate(0, bodyR * 0.15), 3.5, 2.3, false, mouth);
    }
  }

  void _leaf(Canvas canvas, Offset base, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx + r, base.dy - r, base.dx, base.dy - r * 1.6)
      ..quadraticBezierTo(base.dx - r, base.dy - r, base.dx, base.dy);
    canvas.drawPath(path, p);
  }

  void _teardrop(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - r * 1.3)
      ..quadraticBezierTo(center.dx + r * 1.2, center.dy, center.dx, center.dy + r)
      ..quadraticBezierTo(center.dx - r * 1.2, center.dy, center.dx, center.dy - r * 1.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PetPainter old) =>
      old.species != species ||
      old.stage != stage ||
      old.color != color ||
      old.mood != mood ||
      old.accessoryCount != accessoryCount;
}
