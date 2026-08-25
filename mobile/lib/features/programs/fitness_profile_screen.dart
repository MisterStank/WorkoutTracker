import 'package:flutter/material.dart';

import 'fitness_profile_form.dart';

/// Standalone entry point (Programs tab sparkle icon) for the
/// personalization form. The form itself lives in [FitnessProfileForm] so
/// it can also be embedded, without this screen's chrome, as the last page
/// of the first-run onboarding wizard.
class FitnessProfileScreen extends StatelessWidget {
  const FitnessProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personalize a program')),
      body: const FitnessProfileForm(),
    );
  }
}
