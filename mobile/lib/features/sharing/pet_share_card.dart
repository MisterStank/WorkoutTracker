import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../pet/pet_avatar.dart';
import '../pet/pet_models.dart';

/// A shareable "meet my companion" card — fixed size, fixed dark-on-brick-red
/// palette regardless of the app's current theme, so the exported image
/// looks the same for everyone. Mirrors [PrShareCard] / [WorkoutSummaryShareCard].
class PetShareCard extends StatelessWidget {
  const PetShareCard({super.key, required this.pet});

  final Pet pet;

  static const _background = Color(0xFF3D1410);
  static const _accent = Color(0xFFE8663F);
  static const _text = Color(0xFFFFF3ED);

  static String _mood(MoodState s) => switch (s) {
        MoodState.happy => 'Thriving',
        MoodState.content => 'Content',
        MoodState.low => 'A bit down',
        MoodState.neglected => 'Neglected',
      };

  @override
  Widget build(BuildContext context) {
    final accessories = pet.accessories.length;

    return Container(
      width: 340,
      height: 430,
      padding: const EdgeInsets.all(26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_background, Color(0xFF17191A)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MY GYMON',
              style: TextStyle(fontFamily: AppTypography.display, color: _accent, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1.4)),
          const SizedBox(height: 4),
          Text(pet.name,
              style: const TextStyle(fontFamily: AppTypography.display, color: _text, fontSize: 28, fontWeight: FontWeight.w700)),
          Text('${pet.stageLabel} · ${_mood(pet.moodState)}',
              style: TextStyle(fontFamily: AppTypography.body, color: _text.withValues(alpha: 0.8), fontSize: 14)),
          const Spacer(),
          Center(child: PetAvatar(pet: pet, size: 150)),
          const Spacer(),
          Row(
            children: [
              _Stat(value: '${pet.currentStreak}', label: 'DAY STREAK'),
              const SizedBox(width: 28),
              _Stat(value: '$accessories', label: accessories == 1 ? 'ACCESSORY' : 'ACCESSORIES'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _accent, size: 15),
              const SizedBox(width: 6),
              Text('GYMON',
                  style: TextStyle(
                      fontFamily: AppTypography.display, color: _text.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontFamily: AppTypography.mono, color: PetShareCard._text, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
        Text(label,
            style: TextStyle(
                fontFamily: AppTypography.display, color: PetShareCard._accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ],
    );
  }
}
