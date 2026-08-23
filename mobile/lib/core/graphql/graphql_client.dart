import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../storage/token_storage.dart';

/// Backend base URL. In Phase 1 this points at a local `docker compose`
/// API; swap via `--dart-define=API_URL=...` for staging/prod builds.
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080/graphql');

String get _wsUrl => _apiUrl.replaceFirst('http', 'ws');

/// Builds a GraphQL client that attaches the current access token to every
/// request. The auth link re-reads the token on each call (not cached at
/// client-construction time) so a token refresh is picked up immediately.
///
/// Subscriptions are split off to a WebSocketLink: the server can't read a
/// normal Authorization header off a WS handshake, so the token is instead
/// sent as the connection_init payload (see cmd/api/main.go's InitFunc).
GraphQLClient buildGraphQLClient(TokenStorage tokenStorage) {
  final httpLink = HttpLink(_apiUrl);

  final authLink = AuthLink(
    getToken: () async {
      final token = await tokenStorage.readAccessToken();
      return token == null ? null : 'Bearer $token';
    },
  );

  final wsLink = WebSocketLink(
    _wsUrl,
    config: SocketClientConfig(
      autoReconnect: true,
      inactivityTimeout: const Duration(seconds: 30),
      initialPayload: () async {
        final token = await tokenStorage.readAccessToken();
        return {'Authorization': token == null ? '' : 'Bearer $token'};
      },
    ),
  );

  final link = Link.split(_isSubscription, wsLink, authLink.concat(httpLink));

  return GraphQLClient(
    link: link,
    cache: GraphQLCache(),
  );
}

bool _isSubscription(Request request) {
  final definitions = request.operation.document.definitions.whereType<OperationDefinitionNode>();
  final definition = definitions.firstWhere(
    (d) => request.operation.operationName == null || d.name?.value == request.operation.operationName,
    orElse: () => definitions.first,
  );
  return definition.type == OperationType.subscription;
}
