import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/workout/set_input_validation.dart';

void main() {
  group('validateReps', () {
    test('accepts a normal rep count', () => expect(validateReps('5'), isNull));
    test('rejects non-numbers', () => expect(validateReps('abc'), isNotNull));
    test('rejects zero', () => expect(validateReps('0'), isNotNull));
    test('rejects negatives', () => expect(validateReps('-3'), isNotNull));
    test('rejects over 100', () => expect(validateReps('101'), isNotNull));
    test('trims whitespace', () => expect(validateReps('  8 '), isNull));
  });

  group('validateWeight', () {
    test('accepts a normal weight', () => expect(validateWeight('100', maxWeightInUnit: 1000), isNull));
    test('rejects non-numbers', () => expect(validateWeight('', maxWeightInUnit: 1000), isNotNull));
    test('rejects negative when not allowed', () => expect(validateWeight('-5', maxWeightInUnit: 1000), isNotNull));
    test('allows zero/negative for bodyweight', () {
      expect(validateWeight('0', maxWeightInUnit: 1000, allowNonPositive: true), isNull);
      expect(validateWeight('-15', maxWeightInUnit: 1000, allowNonPositive: true), isNull);
    });
    test('rejects above the unit max', () => expect(validateWeight('2500', maxWeightInUnit: 2205), isNotNull));
  });

  group('validateRpe', () {
    test('accepts empty (optional)', () => expect(validateRpe(''), isNull));
    test('accepts half steps', () => expect(validateRpe('8.5'), isNull));
    test('rejects out of range', () => expect(validateRpe('99'), isNotNull));
    test('rejects non-half steps', () => expect(validateRpe('8.3'), isNotNull));
    test('rejects text', () => expect(validateRpe('hard'), isNotNull));
  });
}
