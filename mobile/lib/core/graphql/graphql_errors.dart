import 'package:graphql_flutter/graphql_flutter.dart';

/// Turns an [OperationException] into a message worth showing a user.
///
/// The backend sends clean, user-facing strings for known errors (e.g.
/// "reps must be between 1 and 100, and weight between 0 and 1000 kg") as
/// GraphQL errors, and masks everything else to a generic message. So the
/// first GraphQL error message is almost always the right thing to surface —
/// far better than dumping [OperationException.toString()], which includes
/// link failures and stack-shaped exception lists.
String readableGraphQLError(OperationException? exception) {
  final graphqlErrors = exception?.graphqlErrors ?? const [];
  if (graphqlErrors.isNotEmpty && graphqlErrors.first.message.isNotEmpty) {
    return graphqlErrors.first.message;
  }
  if (exception?.linkException != null) {
    return 'Something went wrong. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Convenience for the `if (result.hasException) throw ...` guard repeated
/// across repositories.
Exception graphQLException(OperationException? exception) => Exception(readableGraphQLError(exception));
