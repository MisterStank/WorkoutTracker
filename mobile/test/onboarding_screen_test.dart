import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gymon/features/onboarding/onboarding_prefs.dart';
import 'package:gymon/features/onboarding/onboarding_screen.dart';
import 'package:gymon/features/pet/pet_models.dart';
import 'package:gymon/features/pet/pet_provider.dart';

// The createPet and personalization steps need a live GraphQL client, so
// tests either stop before them or override [petProvider] so the flow skips
// the create step entirely.

Pet _pet() => const Pet(
      id: 'p1',
      name: 'Pixel',
      species: PetSpecies.sprout,
      color: PetColor.green,
      stage: PetStage.hatchling,
      stageLabel: 'Hatchling',
      mood: 80,
      moodState: MoodState.happy,
      currentStreak: 2,
      longestStreak: 2,
      workoutsToNextStage: 3,
      hatchedAt: null,
      appearance: PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: '', layers: []),
      accessories: [],
      newlyUnlocked: [],
    );

class _FixedPetNotifier extends PetNotifier {
  _FixedPetNotifier(this._value);
  final Pet? _value;
  @override
  Future<Pet?> build() async => _value;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('welcome step has no Skip and leads into choosing a companion', (tester) async {
    final container = ProviderContainer(overrides: [
      petProvider.overrideWith(() => _FixedPetNotifier(null)),
    ]);
    addTearDown(container.dispose);
    await _pump(tester, container);
    await tester.pump();

    expect(find.text('Welcome to Gymon'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Skip'), findsNothing);
    expect(container.read(onboardingCompleteProvider), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Choose my companion'));
    await tester.pump();

    // The pet-creation step (PetOnboardingView) is now showing.
    expect(find.text('Species'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Hatch your companion'), findsOneWidget);
  });

  testWidgets('with a pet already present, the flow is welcome -> how-it-works -> done', (tester) async {
    var done = false;
    final container = ProviderContainer(overrides: [
      petProvider.overrideWith(() => _FixedPetNotifier(_pet())),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: OnboardingScreen(showPersonalization: false, onDone: () => done = true)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Welcome to Gymon'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Show me'));
    await tester.pump();

    expect(find.text('How Pixel grows'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, "I'm ready"));
    await tester.pump();

    expect(done, isTrue);
  });
}
