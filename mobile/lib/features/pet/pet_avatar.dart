import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_models.dart';
import 'pet_palette.dart';

/// Placeholder companion art — a soft blob mascot drawn with a [CustomPainter],
/// with a gentle idle animation. Replaced by hand-drawn assets per
/// docs/PET_PLAN.md; the server sends asset *keys* so that swap needs no
/// backend change.
class PetAvatar extends StatefulWidget {
  const PetAvatar({super.key, required this.pet, this.size = 160});

  final Pet pet;
  final double size;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with SingleTickerProviderStateMixin {
  // 4s loop, sampled at ~30fps.
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  static const _frames = 120;

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The egg→hatchling gate is 5 finished workouts; the shell cracks more as
  /// that count is approached.
  static double _eggCrack(Pet pet) {
    if (pet.stage != PetStage.egg) return 0;
    final left = pet.workoutsToNextStage;
    return left == null ? 0 : (1 - (left / 5).clamp(0.0, 1.0)).toDouble();
  }

  _PetPainter _painter(double t) {
    final pet = widget.pet;
    final neglected = pet.moodState == MoodState.neglected;
    return _PetPainter(
      species: pet.species,
      stage: pet.stage,
      palette: neglected ? neglectedPalette(pet.color) : petPalette(pet.color),
      mood: pet.moodState,
      t: t,
      eggCrack: _eggCrack(pet),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _reduceMotion
            ? CustomPaint(painter: _painter(0))
            : AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => CustomPaint(
                  painter: _painter((_controller.value * _frames).round() / _frames),
                ),
              ),
      ),
    );
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({
    required this.species,
    required this.stage,
    required this.palette,
    required this.mood,
    required this.t,
    required this.eggCrack,
  });

  final PetSpecies species;
  final PetStage stage;
  final PetPalette palette;
  final MoodState mood;
  final double t; // 0..1 loop position
  final double eggCrack;

  static const _u = 100.0;

  // --- motion ---------------------------------------------------------------

  double get _tau => t * 2 * math.pi;
  double get _breath => math.sin(_tau);
  double get _bounce => mood == MoodState.happy ? math.max(0.0, math.sin(_tau * 2)) * 3.0 : 0.0;
  double get _wobble => math.sin(_tau * 1.5);

  /// 1 = eyes open, 0 = shut. A quick blink near the end of the loop.
  double get _eyeOpen {
    if (mood == MoodState.neglected) return 0;
    if (t < 0.86 || t > 0.98) return 1;
    final n = (t - 0.86) / 0.12; // 0..1 across the blink
    return (1 - math.sin(n * math.pi)).clamp(0.0, 1.0);
  }

  // --- paint ---------------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / _u;
    canvas.save();
    canvas.translate((size.width - _u * s) / 2, (size.height - _u * s) / 2);
    canvas.scale(s);

    final line = Paint()
      ..color = palette.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Paint()..color = palette.body;
    final belly = Paint()..color = palette.belly;
    final feature = Paint()..color = palette.feature;

    if (stage == PetStage.egg) {
      _paintShadow(canvas, 0);
      _paintEgg(canvas, body, belly, line);
      canvas.restore();
      return;
    }

    _paintShadow(canvas, _bounce);

    // Body grows with stage; neglected deflates a touch.
    final scale = 0.62 + 0.11 * stage.index + (mood == MoodState.neglected ? -0.03 : 0);
    final r = 30.0 * scale;
    final cy = 58.0 - _bounce + (mood == MoodState.neglected ? 3 : 0);
    final center = Offset(50, cy);
    final w = r * (1 + 0.03 * _breath);
    final h = r * ((mood == MoodState.neglected ? 0.98 : 1.06) - 0.03 * _breath);

    if (stage == PetStage.champion) _paintSparkleRing(canvas, center, r);

    _paintFeet(canvas, center, r, body, line);
    _paintFeature(canvas, center, r, feature, line);

    final bodyRect = Rect.fromCenter(center: center, width: w * 2, height: h * 2);
    canvas.drawOval(bodyRect, body);
    canvas.drawOval(bodyRect, line);
    // little arm nubs
    for (final side in const [-1.0, 1.0]) {
      final arm = Rect.fromCenter(center: center.translate(side * w * 0.92, h * 0.35), width: r * 0.34, height: r * 0.46);
      canvas.drawOval(arm, body);
      canvas.drawOval(arm, line);
    }
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, h * 0.42), width: w * 1.15, height: h * 1.0),
      belly,
    );

    _paintFace(canvas, center, r);

    if (mood == MoodState.happy) _paintPop(canvas, center, r);

    canvas.restore();
  }

  void _paintShadow(Canvas canvas, double lift) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 90), width: 44 - lift * 2.5, height: 8 - lift * 0.7),
      Paint()..color = palette.outline.withValues(alpha: 0.13),
    );
  }

  void _paintFeet(Canvas canvas, Offset c, double r, Paint body, Paint line) {
    for (final side in const [-1.0, 1.0]) {
      final foot = Rect.fromCenter(center: Offset(c.dx + side * r * 0.5, c.dy + r * 0.98), width: r * 0.6, height: r * 0.4);
      canvas.drawOval(foot, body);
      canvas.drawOval(foot, line);
    }
  }

  void _paintFeature(Canvas canvas, Offset c, double r, Paint feature, Paint line) {
    // Sit the crown feature just above the body top so it isn't swallowed by
    // the body oval (drawn after this).
    final top = Offset(c.dx, c.dy - r * 1.12);
    final sway = _breath * 0.06;
    switch (species) {
      case PetSpecies.sprout:
        for (final dir in const [-1.0, 0.7]) {
          canvas.save();
          canvas.translate(top.dx, top.dy + r * 0.1);
          canvas.rotate(dir * 0.5 + sway);
          final leaf = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(r * 0.28, -r * 0.22, r * 0.05, -r * 0.55)
            ..quadraticBezierTo(-r * 0.16, -r * 0.24, 0, 0)
            ..close();
          canvas.drawPath(leaf, feature);
          canvas.drawPath(leaf, line);
          canvas.restore();
        }
      case PetSpecies.ember:
        canvas.save();
        canvas.translate(top.dx, top.dy + r * 0.15);
        canvas.rotate(sway);
        final flame = Path()
          ..moveTo(-r * 0.3, r * 0.1)
          ..quadraticBezierTo(-r * 0.34, -r * 0.5, 0, -r * 0.78)
          ..quadraticBezierTo(r * 0.12, -r * 0.4, r * 0.32, -r * 0.66)
          ..quadraticBezierTo(r * 0.42, -r * 0.2, r * 0.3, r * 0.1)
          ..quadraticBezierTo(0, r * 0.24, -r * 0.3, r * 0.1)
          ..close();
        canvas.drawPath(flame, feature);
        canvas.drawPath(flame, line);
        canvas.restore();
      case PetSpecies.pebble:
        // three rounded stones on the crown
        final stones = <Rect>[
          Rect.fromCenter(center: Offset(top.dx - r * 0.4, top.dy + r * 0.42), width: r * 0.62, height: r * 0.52),
          Rect.fromCenter(center: Offset(top.dx + r * 0.05, top.dy + r * 0.18), width: r * 0.78, height: r * 0.64),
          Rect.fromCenter(center: Offset(top.dx + r * 0.46, top.dy + r * 0.44), width: r * 0.56, height: r * 0.48),
        ];
        for (final s in stones) {
          canvas.drawOval(s, feature);
        }
        for (final s in stones) {
          canvas.drawOval(s, line);
        }
      case PetSpecies.drift:
        // stub wings on the body sides
        for (final side in const [-1.0, 1.0]) {
          final wing = Rect.fromCenter(center: Offset(c.dx + side * r * 1.05, c.dy), width: r * 0.5, height: r * 0.8);
          canvas.drawOval(wing, feature);
          canvas.drawOval(wing, line);
        }
        // a little cloud puff on the crown
        final puffs = <Offset>[
          Offset(top.dx - r * 0.42, top.dy + r * 0.5),
          Offset(top.dx + r * 0.02, top.dy + r * 0.32),
          Offset(top.dx + r * 0.46, top.dy + r * 0.5),
        ];
        const radii = [0.34, 0.44, 0.32];
        final cloud = Path();
        for (var i = 0; i < puffs.length; i++) {
          cloud.addOval(Rect.fromCircle(center: puffs[i], radius: radii[i] * r));
        }
        canvas.drawPath(cloud, feature);
        canvas.drawPath(cloud, line);
    }
  }

  void _paintFace(Canvas canvas, Offset c, double r) {
    final ink = Paint()..color = palette.outline;
    final stroke = Paint()
      ..color = palette.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final faceY = c.dy - r * 0.06;
    final eyeDx = r * 0.36;
    final open = _eyeOpen;
    final droop = mood == MoodState.low || mood == MoodState.neglected;

    // blush — always on. A plain soft-pink patch (not blended with the body,
    // which would muddy to olive on a green pet).
    for (final side in const [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(c.dx + side * r * 0.58, faceY + r * 0.17), width: r * 0.34, height: r * 0.22),
        Paint()..color = const Color(0xFFF7909E).withValues(alpha: 0.75),
      );
    }

    for (final side in const [-1.0, 1.0]) {
      final e = Offset(c.dx + side * eyeDx, faceY);
      switch (mood) {
        case MoodState.happy:
          canvas.drawArc(Rect.fromCenter(center: e.translate(0, r * 0.04), width: r * 0.34, height: r * 0.34), math.pi + 0.5, math.pi - 1.0, false, stroke);
        case MoodState.neglected:
          canvas.drawArc(Rect.fromCenter(center: e, width: r * 0.3, height: r * 0.3), 0.5, math.pi - 1.0, false, stroke);
        case MoodState.low:
          // half-lid
          canvas.drawOval(Rect.fromCenter(center: e.translate(0, r * 0.03), width: r * 0.22, height: r * 0.2 * open), ink);
          canvas.drawLine(e.translate(-r * 0.13, -r * 0.06), e.translate(r * 0.13, -r * 0.06), stroke);
        case MoodState.content:
          canvas.drawOval(Rect.fromCenter(center: e, width: r * 0.22, height: r * 0.3 * open), ink);
          if (open > 0.4) {
            canvas.drawCircle(e.translate(-r * 0.06, -r * 0.07), r * 0.05, Paint()..color = Colors.white.withValues(alpha: 0.9));
          }
      }
    }

    // nose-mouth
    final my = faceY + r * (droop ? 0.42 : 0.34);
    final mRect = Rect.fromCenter(center: Offset(c.dx, my), width: r * 0.44, height: r * 0.32);
    switch (mood) {
      case MoodState.happy:
        final mouth = Path()
          ..moveTo(mRect.left, mRect.top)
          ..quadraticBezierTo(c.dx, mRect.bottom + r * 0.06, mRect.right, mRect.top)
          ..close();
        canvas.drawPath(mouth, ink);
      case MoodState.content:
        canvas.drawArc(mRect, 0.35, math.pi - 0.7, false, stroke);
      case MoodState.low:
        canvas.drawLine(mRect.centerLeft, mRect.centerRight, stroke);
      case MoodState.neglected:
        // small downturn
        canvas.drawArc(mRect.translate(0, r * 0.12), math.pi + 0.5, math.pi - 1.0, false, stroke);
        // tear
        final tear = Path()
          ..moveTo(c.dx - eyeDx, faceY + r * 0.14)
          ..quadraticBezierTo(c.dx - eyeDx - r * 0.09, faceY + r * 0.3, c.dx - eyeDx, faceY + r * 0.4)
          ..quadraticBezierTo(c.dx - eyeDx + r * 0.09, faceY + r * 0.3, c.dx - eyeDx, faceY + r * 0.14)
          ..close();
        canvas.drawPath(tear, Paint()..color = const Color(0xFF7FB4E6));
    }
  }

  void _sparkle(Canvas canvas, Offset c, double rad, Paint p) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final rr = i.isEven ? rad : rad * 0.34;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  void _paintSparkleRing(Canvas canvas, Offset c, double r) {
    final p = Paint()..color = palette.feature;
    for (var i = 0; i < 5; i++) {
      final a = _tau * 0.4 + i * 2 * math.pi / 5;
      _sparkle(canvas, c + Offset(math.cos(a), math.sin(a)) * (r * 1.5), 2.4, p);
    }
  }

  void _paintPop(Canvas canvas, Offset c, double r) {
    final pulse = (math.sin(_tau * 2) * 0.5 + 0.5);
    if (pulse < 0.2) return;
    _sparkle(canvas, Offset(c.dx + r * 0.9, c.dy - r * 0.9), 3.0 * pulse, Paint()..color = Colors.white.withValues(alpha: 0.85 * pulse));
  }

  void _paintEgg(Canvas canvas, Paint body, Paint belly, Paint line) {
    canvas.save();
    canvas.translate(50, 74);
    canvas.rotate(_wobble * 0.05);
    canvas.translate(-50, -74);

    const cx = 50.0, top = 26.0, bot = 90.0;
    const wLow = 27.0, wHigh = 20.0;
    final egg = Path()
      ..moveTo(cx, top)
      ..cubicTo(cx + wHigh, top, cx + wLow, 48, cx + wLow, 60)
      ..cubicTo(cx + wLow, bot - 8, cx + wLow * 0.6, bot, cx, bot)
      ..cubicTo(cx - wLow * 0.6, bot, cx - wLow, bot - 8, cx - wLow, 60)
      ..cubicTo(cx - wLow, 48, cx - wHigh, top, cx, top)
      ..close();
    canvas.drawPath(egg, body);
    canvas.drawPath(egg, line);
    canvas.drawOval(Rect.fromCenter(center: const Offset(42, 48), width: 11, height: 15), belly);

    if (eggCrack > 0) {
      final crack = Paint()
        ..color = palette.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(60, 44)
        ..lineTo(56, 50)
        ..lineTo(61, 55);
      if (eggCrack > 0.5) {
        path.lineTo(56, 62);
        path.lineTo(60, 69);
      }
      canvas.drawPath(path, crack);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PetPainter old) =>
      old.species != species ||
      old.stage != stage ||
      old.mood != mood ||
      old.palette.body != palette.body ||
      old.eggCrack != eggCrack ||
      old.t != t;
}
