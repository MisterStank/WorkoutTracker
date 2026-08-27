import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/workout/workout_models.dart';

void main() {
  test('Exercise.fromJson parses the custom-exercise fields', () {
    final e = Exercise.fromJson({
      'id': 'x',
      'name': 'Landmine Press',
      'category': 'push',
      'muscleGroups': ['shoulders', 'chest'],
      'equipment': 'barbell',
      'isCustom': true,
      'instructions': '',
    });
    expect(e.muscleGroups, ['shoulders', 'chest']);
    expect(e.equipment, 'barbell');
    expect(e.isCustom, isTrue);
    expect(e.isBodyweight, isFalse);
  });

  test('Exercise.fromJson tolerates missing optional fields (older responses)', () {
    final e = Exercise.fromJson({'id': 'x', 'name': 'Squat', 'category': 'legs'});
    expect(e.muscleGroups, isEmpty);
    expect(e.equipment, '');
    expect(e.isCustom, isFalse);
  });

  test('isBodyweight is true for bodyweight equipment', () {
    final e = Exercise.fromJson({'id': 'x', 'name': 'Pull-Up', 'category': 'pull', 'equipment': 'bodyweight'});
    expect(e.isBodyweight, isTrue);
  });
}
