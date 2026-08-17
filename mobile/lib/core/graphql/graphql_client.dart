import 'package:graphql_flutter/graphql_flutter.dart';

import '../storage/token_storage.dart';

/// Backend base URL. In Phase 1 this points at a local `docker compose`
/// API; swap via `--dart-define=API_URL=...` for staging/prod builds.
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080/graphql');

/// Builds a GraphQL client that attaches the current access token to every
/// request. The auth link re-reads the token on each call (not cached at
/// client-construction time) so a token refresh is picked up immediately.
GraphQLClient buildGraphQLClient(TokenStorage tokenStorage) {
  final httpLink = HttpLink(_apiUrl);

  final authLink = AuthLink(
    getToken: () async {
      final token = await tokenStorage.readAccessToken();
      return token == null ? null : 'Bearer $token';
    },
  );

  return GraphQLClient(
    link: authLink.concat(httpLink),
    cache: GraphQLCache(),
  );
}
