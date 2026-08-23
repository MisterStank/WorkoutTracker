/// Mirrors the phased-roadmap intent (PLAN.md section 6): auth is the first
/// piece of app state, modeled explicitly rather than as loose booleans.
sealed class AuthState {
  const AuthState();
}

/// Shown only once, on app launch, while we check for a stored session.
/// Kept distinct from AuthAuthenticating so AuthGate can show a splash
/// screen here but let LoginScreen own its own inline spinner during a
/// user-initiated login/signup submission.
class AuthRestoring extends AuthState {
  const AuthRestoring();
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
