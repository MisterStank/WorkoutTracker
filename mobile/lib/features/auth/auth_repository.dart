import 'package:graphql_flutter/graphql_flutter.dart';

/// Thin wrapper around the generated GraphQL operations for auth. Kept
/// separate from AuthNotifier so the notifier's state-transition logic can
/// be unit-tested against a fake repository.
class AuthRepository {
  AuthRepository(this._client);

  final GraphQLClient _client;

  static const _authPayloadFields = '''
    user { id email displayName timezone createdAt }
    accessToken
    refreshToken
  ''';

  Future<AuthPayloadResult> signup({
    required String email,
    required String password,
    required String displayName,
  }) => _mutate('signup', '''
        mutation Signup(\$email: String!, \$password: String!, \$displayName: String!) {
          signup(email: \$email, password: \$password, displayName: \$displayName) { $_authPayloadFields }
        }
      ''', {'email': email, 'password': password, 'displayName': displayName});

  Future<AuthPayloadResult> login({required String email, required String password}) => _mutate(
        'login',
        '''
        mutation Login(\$email: String!, \$password: String!) {
          login(email: \$email, password: \$password) { $_authPayloadFields }
        }
      ''',
        {'email': email, 'password': password},
      );

  Future<AuthPayloadResult> refresh({required String refreshToken}) => _mutate(
        'refreshToken',
        '''
        mutation Refresh(\$refreshToken: String!) {
          refreshToken(refreshToken: \$refreshToken) { $_authPayloadFields }
        }
      ''',
        {'refreshToken': refreshToken},
      );

  /// Fetches the current user using whatever access token the GraphQL
  /// client's auth link attaches. Returns null if there's no valid session
  /// (no token, expired token, or the server rejects it) rather than
  /// throwing, since "not logged in" is an expected outcome here.
  Future<UserResult?> me() async {
    final result = await _client.query(QueryOptions(
      document: gql('query Me { me { id email displayName } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) return null;
    final user = result.data?['me'] as Map<String, dynamic>?;
    if (user == null) return null;
    return UserResult(
      userId: user['id'] as String,
      email: user['email'] as String,
      displayName: user['displayName'] as String,
    );
  }

  Future<void> logout({required String refreshToken}) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation Logout(\$refreshToken: String!) {
          logout(refreshToken: \$refreshToken)
        }
      '''),
      variables: {'refreshToken': refreshToken},
    ));
    if (result.hasException) {
      throw Exception(result.exception.toString());
    }
  }

  Future<AuthPayloadResult> _mutate(
    String operationField,
    String document,
    Map<String, dynamic> variables,
  ) async {
    final result = await _client.mutate(MutationOptions(document: gql(document), variables: variables));
    if (result.hasException) {
      throw Exception(result.exception.toString());
    }
    final payload = result.data![operationField] as Map<String, dynamic>;
    final user = payload['user'] as Map<String, dynamic>;
    return AuthPayloadResult(
      userId: user['id'] as String,
      email: user['email'] as String,
      displayName: user['displayName'] as String,
      accessToken: payload['accessToken'] as String,
      refreshToken: payload['refreshToken'] as String,
    );
  }
}

class AuthPayloadResult {
  const AuthPayloadResult({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String email;
  final String displayName;
  final String accessToken;
  final String refreshToken;
}

class UserResult {
  const UserResult({required this.userId, required this.email, required this.displayName});

  final String userId;
  final String email;
  final String displayName;
}
