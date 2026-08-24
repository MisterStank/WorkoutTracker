import 'package:flutter/material.dart';

/// Shared wrapper for the login and signup screens: no AppBar, a wordmark
/// up top standing in for a logo (no image asset exists in this repo), then
/// whatever form content the screen provides underneath. Kept deliberately
/// simple — this is a login screen, not a marketing splash.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.fitness_center, size: 40, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'WorkoutTracker',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 48),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// The loading-state spinner for a submit button, sized to fit inside a
/// normal button instead of ballooning it — an unconstrained
/// CircularProgressIndicator otherwise defaults to ~36-40px tall.
class AuthButtonSpinner extends StatelessWidget {
  const AuthButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.onPrimary),
    );
  }
}
