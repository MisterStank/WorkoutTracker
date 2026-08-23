import 'package:graphql_flutter/graphql_flutter.dart';

import 'analytics_models.dart';

/// Thin wrapper around the generated GraphQL operations for analytics,
/// mirroring WorkoutRepository's shape.
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final GraphQLClient _client;

  Future<List<ProgressPoint>> progressOverTime({required String exerciseId, int days = 90}) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query ProgressOverTime(\$exerciseId: UUID!, \$days: Int!) {
          progressOverTime(exerciseId: \$exerciseId, days: \$days) { day totalVolume maxWeight setCount }
        }
      '''),
      variables: {'exerciseId': exerciseId, 'days': days},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['progressOverTime'] as List<dynamic>;
    return list.map((p) => ProgressPoint.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<ProgressPoint>> volumeTrend({int days = 90}) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query VolumeTrend(\$days: Int!) {
          volumeTrend(days: \$days) { day totalVolume maxWeight setCount }
        }
      '''),
      variables: {'days': days},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['volumeTrend'] as List<dynamic>;
    return list.map((p) => ProgressPoint.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<BodyMetric>> bodyMetrics({String metricType = 'bodyweight_kg', int days = 90}) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query BodyMetrics(\$metricType: String!, \$days: Int!) {
          bodyMetrics(metricType: \$metricType, days: \$days) { id metricType value recordedAt }
        }
      '''),
      variables: {'metricType': metricType, 'days': days},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['bodyMetrics'] as List<dynamic>;
    return list.map((m) => BodyMetric.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<BodyMetric> logBodyMetric({String metricType = 'bodyweight_kg', required double value}) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation LogBodyMetric(\$metricType: String!, \$value: Float!) {
          logBodyMetric(metricType: \$metricType, value: \$value) { id metricType value recordedAt }
        }
      '''),
      variables: {'metricType': metricType, 'value': value},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return BodyMetric.fromJson(result.data!['logBodyMetric'] as Map<String, dynamic>);
  }
}
