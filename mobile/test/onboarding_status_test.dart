import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/onboarding/onboarding_status.dart';

void main() {
  group('decideOnboarding', () {
    test('brand-new user sees the tour and the personalize step', () {
      final d = decideOnboarding(hasProfile: false, hasProgram: false);
      expect(d.isReturningUser, isFalse);
      expect(d.showPersonalization, isTrue);
    });

    test('user with a saved profile is treated as returning', () {
      final d = decideOnboarding(hasProfile: true, hasProgram: false);
      expect(d.isReturningUser, isTrue);
      expect(d.showPersonalization, isFalse);
    });

    test('user with a generated program is treated as returning', () {
      final d = decideOnboarding(hasProfile: false, hasProgram: true);
      expect(d.isReturningUser, isTrue);
      expect(d.showPersonalization, isFalse);
    });
  });
}
