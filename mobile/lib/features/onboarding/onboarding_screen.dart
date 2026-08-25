import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../programs/fitness_profile_form.dart';
import 'onboarding_prefs.dart';

class _Slide {
  const _Slide({required this.icon, required this.title, required this.description});
  final IconData icon;
  final String title;
  final String description;
}

const _slides = [
  _Slide(
    icon: Icons.bolt_outlined,
    title: 'Log workouts fast',
    description: 'Reps, weight, and effort in a couple of taps — sets you log offline sync automatically once you\'re back online.',
  ),
  _Slide(
    icon: Icons.checklist_outlined,
    title: 'Templates & personalized programs',
    description: 'Build a template by hand, or answer a few questions and get a full multi-day training split generated for you.',
  ),
  _Slide(
    icon: Icons.show_chart,
    title: 'Progress & personal records',
    description: 'Every set is checked against your history — hit a new heaviest weight, volume, or estimated 1RM and we\'ll flag it.',
  ),
  _Slide(
    icon: Icons.ios_share,
    title: 'Share your stats',
    description: 'Turn a new PR or a finished workout into a shareable image, ready for your device\'s normal share sheet.',
  ),
];

/// First-run tutorial: a few intro slides followed by the same
/// personalization form used from the Templates tab. Every step can be
/// skipped — either the whole tour (visible on every intro slide) or just
/// the personalization step once reached.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  void _complete() => markOnboardingComplete(ref);

  void _next() {
    _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onIntroSlide = _page < _slides.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (onIntroSlide)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(onPressed: _complete, child: const Text('Skip')),
                ),
              ),
            Expanded(
              // Keyed so Flutter's unkeyed-list reconciliation can't confuse
              // this for a different widget when the Skip button above (or
              // the dots/button below) appear or disappear and shift this
              // Expanded's position within Column.children — without a key,
              // that shift was enough to make Flutter tear down and recreate
              // the PageView (resetting it to page 0) the moment the intro
              // chrome hid on reaching the last page.
              key: const ValueKey('onboarding-pageview'),
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final slide in _slides) _IntroSlideView(slide: slide),
                  FitnessProfileForm(onSkip: _complete, onGenerated: _complete),
                ],
              ),
            ),
            if (onIntroSlide) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_page == _slides.length - 1 ? 'Get started' : 'Next'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntroSlideView extends StatelessWidget {
  const _IntroSlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(slide.icon, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          Text(slide.title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            slide.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
