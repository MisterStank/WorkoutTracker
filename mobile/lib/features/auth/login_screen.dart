import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'auth_scaffold.dart';
import 'auth_state.dart';
import 'auth_validation.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _clientError;

  void _submit() {
    final error = validateEmail(_emailController.text) ??
        (_passwordController.text.isEmpty ? 'Enter your password' : null);
    setState(() => _clientError = error);
    if (error != null) return;
    ref.read(authProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState is AuthAuthenticating;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Log in', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
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
          if (_clientError != null || authState is AuthError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _clientError ?? (authState as AuthError).message,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          FilledButton(
            onPressed: isLoading ? null : _submit,
            child: isLoading ? const AuthButtonSpinner() : const Text('Log in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: isLoading
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
            child: const Text("Don't have an account? Sign up"),
          ),
        ],
      ),
    );
  }
}
