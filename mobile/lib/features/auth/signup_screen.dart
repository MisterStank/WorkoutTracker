import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'auth_scaffold.dart';
import 'auth_state.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState is AuthAuthenticating;

    // SignupScreen is pushed on top of the LoginScreen route that AuthGate
    // (the MaterialApp's home) returns. AuthGate swapping to
    // WorkoutHomeScreen on success only changes what's underneath — this
    // pushed route has to pop itself, or the user would end up "stuck"
    // looking at a still-mounted signup form.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Create an account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 24),
          if (authState is AuthError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(authState.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ),
          FilledButton(
            onPressed: isLoading
                ? null
                : () => ref.read(authProvider.notifier).signup(
                      email: _emailController.text.trim(),
                      password: _passwordController.text,
                      displayName: _displayNameController.text.trim(),
                    ),
            child: isLoading ? const AuthButtonSpinner() : const Text('Sign up'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Already have an account? Log in'),
          ),
        ],
      ),
    );
  }
}
