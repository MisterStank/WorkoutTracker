import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/features/pet/pet_avatar.dart';
import 'package:gymon/features/pet/pet_models.dart';
import 'package:gymon/features/pet/pet_palette.dart';

Pet _pet(PetSpecies s, PetStage st, MoodState m, {int? toNext = 3}) => Pet(
      id: 'p',
      name: 'Pixel',
      species: s,
      color: PetColor.blue,
      stage: st,
      stageLabel: st.name,
      mood: 50,
      moodState: m,
      currentStreak: 0,
      longestStreak: 0,
      workoutsToNextStage: toNext,
      hatchedAt: null,
      appearance: const PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: '', layers: []),
      accessories: const [],
      newlyUnlocked: const [],
    );

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
    );

void main() {
  test('every PetColor resolves to a palette; neglected is drained', () {
    for (final c in PetColor.values) {
      final p = petPalette(c);
      expect(p.outline, isNot(equals(p.body)));
      expect(neglectedPalette(c).body, isNot(equals(p.body)));
      expect(petColorSwatch(c), p.body);
    }
  });

  testWidgets('paints every species x stage x mood without throwing', (tester) async {
    for (final s in PetSpecies.values) {
      for (final st in PetStage.values) {
        for (final m in MoodState.values) {
          await tester.pumpWidget(_host(PetAvatar(pet: _pet(s, st, m), size: 120)));
          expect(tester.takeException(), isNull, reason: '$s / $st / $m');
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stays stable across the animation loop', (tester) async {
    await tester.pumpWidget(_host(PetAvatar(pet: _pet(PetSpecies.ember, PetStage.adult, MoodState.happy), size: 160)));
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion renders and runs no ticker', (tester) async {
    await tester.pumpWidget(_host(PetAvatar(pet: _pet(PetSpecies.sprout, PetStage.juvenile, MoodState.content), size: 140), reduceMotion: true));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(); // would time out if a ticker were running
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('egg renders across the hatch-progress range', (tester) async {
    for (final n in <int?>[null, 5, 2, 0]) {
      await tester.pumpWidget(_host(PetAvatar(pet: _pet(PetSpecies.drift, PetStage.egg, MoodState.content, toNext: n), size: 120)));
      expect(tester.takeException(), isNull, reason: 'toNext=$n');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
