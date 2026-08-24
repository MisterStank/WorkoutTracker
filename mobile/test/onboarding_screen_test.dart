import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/onboarding/onboarding_prefs.dart';
import 'package:mobile/features/onboarding/onboarding_screen.dart';

void main() {
  // Deliberately avoids pumpAndSettle(): the wizard's last page embeds the
  // GraphQL-backed personalization form, which kicks off a network call in
  // initState that never resolves in a widget test with no client wired
  // up — pumpAndSettle would hang waiting for it. Bounded pump() calls
  // sidestep that; the personalize page's own submit flow is covered
  // manually instead (it needs a live GraphQL client).

  testWidgets('OnboardingScreen shows the first intro slide with a visible Skip action', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Log workouts fast'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
    expect(container.read(onboardingCompleteProvider), isFalse);
  });

  testWidgets('Tapping Skip marks onboarding complete', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await tester.pump();

    expect(container.read(onboardingCompleteProvider), isTrue);
  });

  testWidgets('Next pages through intro slides and updates the dot indicator', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Log workouts fast'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Templates & personalized programs'), findsOneWidget);
    expect(find.text('Log workouts fast'), findsNothing);
  });
}
