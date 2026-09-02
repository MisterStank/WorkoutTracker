import 'package:flutter_test/flutter_test.dart';
import 'package:gymon/features/pet/pet_models.dart';

void main() {
  test('Pet.fromJson parses enums, nested appearance and accessories', () {
    final pet = Pet.fromJson({
      'id': 'p1',
      'name': 'Pixel',
      'species': 'EMBER',
      'color': 'BLUE',
      'stage': 'JUVENILE',
      'stageLabel': 'Juvenile',
      'mood': 82,
      'moodState': 'HAPPY',
      'currentStreak': 4,
      'longestStreak': 9,
      'workoutsToNextStage': 12,
      'hatchedAt': '2026-01-01T00:00:00Z',
      'appearance': {
        'bodyAssetKey': 'pet/ember/juvenile',
        'expressionAssetKey': 'expr/happy',
        'tint': 'blue',
        'layers': ['acc/streak_cap_7'],
      },
      'accessories': [
        {
          'accessory': {'id': 'a1', 'code': 'streak_cap_7', 'name': 'Hat', 'slot': 'head', 'unlockHint': 'Reach a 7-day streak'},
          'unlockedAt': '2026-02-01T00:00:00Z',
          'equipped': true,
        }
      ],
      'newlyUnlocked': [],
    });

    expect(pet.species, PetSpecies.ember);
    expect(pet.color, PetColor.blue);
    expect(pet.stage, PetStage.juvenile);
    expect(pet.moodState, MoodState.happy);
    expect(pet.workoutsToNextStage, 12);
    expect(pet.appearance.layers, ['acc/streak_cap_7']);
    expect(pet.accessories.single.equipped, true);
    expect(pet.accessories.single.accessory.slot, 'head');
    expect(pet.isNeglected, false);
  });

  test('Pet.fromJson tolerates null workoutsToNextStage and hatchedAt', () {
    final pet = Pet.fromJson({
      'id': 'p1',
      'name': 'Egg',
      'species': 'SPROUT',
      'color': 'GREEN',
      'stage': 'EGG',
      'stageLabel': 'Egg',
      'mood': 40,
      'moodState': 'CONTENT',
      'currentStreak': 0,
      'longestStreak': 0,
      'workoutsToNextStage': null,
      'hatchedAt': null,
      'appearance': {'bodyAssetKey': '', 'expressionAssetKey': '', 'tint': 'green', 'layers': []},
      'accessories': [],
      'newlyUnlocked': [],
    });
    expect(pet.workoutsToNextStage, isNull);
    expect(pet.hatchedAt, isNull);
  });

  test('enumToGql round-trips to the GraphQL SCREAMING_CASE', () {
    expect(enumToGql(PetSpecies.drift), 'DRIFT');
    expect(enumToGql(PetColor.violet), 'VIOLET');
  });
}
