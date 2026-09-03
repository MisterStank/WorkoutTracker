import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pet/pet_avatar.dart';
import '../pet/pet_models.dart';
import '../pet/pet_onboarding_screen.dart';
import '../pet/pet_provider.dart';
import '../programs/fitness_profile_form.dart';
import 'onboarding_prefs.dart';

/// First-run flow for a freshly-authenticated user. Learn-by-doing rather
/// than a slideshow: they actually create and name their companion, then see
/// exactly how feeding / streaks / neglect work, then optionally set up a
/// training program. The intro steps have no "Skip" — it's three short
/// screens and the middle one is the fun part — so everyone arrives at the
/// app knowing what the companion is for.
enum _Step { welcome, createPet, howItWorks, personalize }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.showPersonalization = true, this.onDone});

  /// Whether the optional "generate a training program" step is shown. False
  /// for a returning user who already has a profile/program, and when
  /// replaying the flow from the menu.
  final bool showPersonalization;

  /// Called when the flow finishes. Defaults to marking first-run onboarding
  /// complete; the replay-from-menu caller pops its route instead.
  final VoidCallback? onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _current = _Step.welcome;

  List<_Step> get _flow {
    final petExists = ref.read(petProvider).valueOrNull != null;
    return [
      _Step.welcome,
      if (!petExists) _Step.createPet,
      _Step.howItWorks,
      if (widget.showPersonalization) _Step.personalize,
    ];
  }

  void _complete() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      markOnboardingComplete(ref);
    }
  }

  void _advance() {
    final flow = _flow;
    final i = flow.indexOf(_current);
    if (i < 0 || i + 1 >= flow.length) {
      _complete();
      return;
    }
    setState(() => _current = flow[i + 1]);
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    final stepIndex = flow.indexOf(_current).clamp(0, flow.length - 1);
    final petName = ref.watch(petProvider).valueOrNull?.name ?? 'your companion';

    final Widget body = switch (_current) {
      _Step.welcome => _WelcomeStep(alreadyHasPet: !flow.contains(_Step.createPet), onNext: _advance),
      _Step.createPet => PetOnboardingView(
          showIntro: false,
          onCreated: () => setState(() => _current = _Step.howItWorks),
        ),
      _Step.howItWorks => _HowItWorksStep(
          petName: petName,
          nextLabel: widget.showPersonalization ? 'Set up a program' : "I'm ready",
          onNext: _advance,
        ),
      _Step.personalize => FitnessProfileForm(onSkip: _complete, onGenerated: _complete),
    };

    // The personalization form carries its own full-screen chrome.
    final showDots = _current != _Step.personalize;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(key: const ValueKey('onboarding-body'), child: body),
            if (showDots)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < flow.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == stepIndex
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Pet _previewEgg() => const Pet(
      id: 'preview',
      name: 'your companion',
      species: PetSpecies.sprout,
      color: PetColor.green,
      stage: PetStage.egg,
      stageLabel: 'Egg',
      mood: 60,
      moodState: MoodState.content,
      currentStreak: 0,
      longestStreak: 0,
      workoutsToNextStage: 5,
      hatchedAt: null,
      appearance: PetAppearance(bodyAssetKey: '', expressionAssetKey: '', tint: '', layers: []),
      accessories: [],
      newlyUnlocked: [],
    );

class _WelcomeStep extends ConsumerWidget {
  const _WelcomeStep({required this.alreadyHasPet, required this.onNext});

  final bool alreadyHasPet;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pet = ref.watch(petProvider).valueOrNull ?? _previewEgg();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PetAvatar(pet: pet, size: 160),
          const SizedBox(height: 32),
          Text('Welcome to Gymon', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            alreadyHasPet
                ? 'A quick refresher on how your companion works.'
                : "Gymon is a companion you raise by training. It hatches from an egg, grows every time you finish a workout, and gets sad if you disappear. Let's set yours up.",
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
            child: Text(alreadyHasPet ? 'Show me' : 'Choose my companion'),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends ConsumerWidget {
  const _HowItWorksStep({required this.petName, required this.nextLabel, required this.onNext});

  final String petName;
  final String nextLabel;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pet = ref.watch(petProvider).valueOrNull;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
            children: [
              if (pet != null) Center(child: PetAvatar(pet: pet, size: 120)),
              const SizedBox(height: 16),
              Text('How $petName grows', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              _Rule(
                icon: Icons.fitness_center,
                title: 'Finish a workout, feed your companion',
                body: 'Every completed workout raises their mood and moves them toward the next evolution.',
              ),
              _Rule(
                icon: Icons.local_fire_department_outlined,
                title: 'Keep a streak, unlock gear',
                body: 'Train most days to build a streak. Streaks, PRs and milestones unlock hats, collars, capes and auras.',
              ),
              _Rule(
                icon: Icons.sentiment_dissatisfied_outlined,
                title: "Don't ghost them",
                body: 'Skip training for a week and $petName gets neglected. A single workout starts bringing them back — nothing is ever lost for good.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tap "Train to feed $petName" on the Companion tab whenever you\'re ready to work out.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(nextLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
