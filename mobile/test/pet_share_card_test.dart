import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/features/pet/pet_models.dart';
import 'package:gymon/features/sharing/pet_share_card.dart';

Pet _pet({int streak = 14, int accessories = 3, MoodState mood = MoodState.happy}) => Pet(
      id: 'p1',
      name: 'Pixel',
      species: PetSpecies.sprout,
      color: PetColor.green,
      stage: PetStage.juvenile,
      stageLabel: 'Juvenile',
      mood: 100,
      moodState: mood,
      currentStreak: streak,
      longestStreak: streak,
      workoutsToNextStage: 18,
      hatchedAt: DateTime(2026, 1, 1),
      appearance: const PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: 'green', layers: []),
      accessories: List.generate(
        accessories,
        (i) => PetAccessory(
          accessory: Accessory(id: 'a$i', code: 'c$i', name: 'Acc $i', slot: 'head', unlockHint: ''),
          unlockedAt: DateTime(2026, 2, 1),
          equipped: false,
        ),
      ),
      newlyUnlocked: const [],
    );

Future<void> _pump(WidgetTester tester, Widget card) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));

void main() {
  group('PetShareCard', () {
    testWidgets('shows the pet name, stage/mood, streak and accessory count', (tester) async {
      await _pump(tester, PetShareCard(pet: _pet(streak: 14, accessories: 3)));

      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('Juvenile · Thriving'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('DAY STREAK'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('ACCESSORIES'), findsOneWidget);
      expect(find.text('GYMON'), findsOneWidget);
    });

    testWidgets('singular accessory label when only one is unlocked', (tester) async {
      await _pump(tester, PetShareCard(pet: _pet(accessories: 1)));
      expect(find.text('ACCESSORY'), findsOneWidget);
    });

    testWidgets('reflects a neglected mood', (tester) async {
      await _pump(tester, PetShareCard(pet: _pet(mood: MoodState.neglected)));
      expect(find.text('Juvenile · Neglected'), findsOneWidget);
    });
  });
}
