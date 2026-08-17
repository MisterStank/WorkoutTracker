import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../core/graphql/graphql_client.dart';
import '../../core/storage/token_storage.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});

final graphQLClientProvider = Provider<GraphQLClient>((ref) {
  return buildGraphQLClient(ref.watch(tokenStorageProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(graphQLClientProvider));
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider), ref.watch(tokenStorageProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repository, this._tokenStorage) : super(const AuthUnauthenticated());

  final AuthRepository _repository;
  final TokenStorage _tokenStorage;

  Future<void> signup({required String email, required String password, required String displayName}) =>
      _authenticate(() => _repository.signup(email: email, password: password, displayName: displayName));

  Future<void> login({required String email, required String password}) =>
      _authenticate(() => _repository.login(email: email, password: password));

  Future<void> _authenticate(Future<AuthPayloadResult> Function() action) async {
    state = const AuthAuthenticating();
    try {
      final result = await action();
      await _tokenStorage.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
      state = AuthAuthenticated(userId: result.userId, email: result.email, displayName: result.displayName);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _repository.logout(refreshToken: refreshToken);
      } catch (_) {
        // best-effort server-side revoke; local session is cleared regardless
      }
    }
    await _tokenStorage.clear();
    state = const AuthUnauthenticated();
  }
}
