/// Mirrors the phased-roadmap intent (PLAN.md section 6): auth is the first
/// piece of app state, modeled explicitly rather than as loose booleans.
sealed class AuthState {
  const AuthState();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.userId, required this.email, required this.displayName});

  final String userId;
  final String email;
  final String displayName;
}

class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}
