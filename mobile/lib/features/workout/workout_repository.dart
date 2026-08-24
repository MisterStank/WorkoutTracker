import 'package:graphql_flutter/graphql_flutter.dart';

import 'workout_models.dart';

/// Thin wrapper around the generated GraphQL operations for workout
/// tracking, mirroring AuthRepository's shape.
class WorkoutRepository {
  WorkoutRepository(this._client);

  final GraphQLClient _client;

  static const _workoutFields = '''
    id startedAt endedAt notes status templateId
    sets { id exerciseId setNumber reps weightKg rpe isWarmup performedAt }
  ''';

  /// Streams every set logged to this workout in real time (GraphQL
  /// subscription over WebSocket, backed by Redis pub/sub server-side) —
  /// used so a second device/tab watching the same workout updates live.
  Stream<LogSetResult> watchWorkoutProgress(String workoutId) {
    final stream = _client.subscribe(SubscriptionOptions(
      document: gql('''
        subscription WorkoutProgressUpdated(\$workoutId: UUID!) {
          workoutProgressUpdated(workoutId: \$workoutId) {
            set { id exerciseId setNumber reps weightKg rpe isWarmup performedAt }
            newRecords { exerciseId recordType value }
          }
        }
      '''),
      variables: {'workoutId': workoutId},
    ));

    return stream.where((result) => !result.hasException && result.data != null).map((result) {
      final payload = result.data!['workoutProgressUpdated'] as Map<String, dynamic>;
      final newRecords = (payload['newRecords'] as List<dynamic>)
          .map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>))
          .toList();
      return LogSetResult(set: WorkoutSet.fromJson(payload['set'] as Map<String, dynamic>), newRecords: newRecords);
    });
  }

  Future<List<Exercise>> exercises({String? search}) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query Exercises(\$search: String) {
          exercises(search: \$search) { id name category }
        }
      '''),
      variables: {'search': search},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['exercises'] as List<dynamic>;
    return list.map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Workout?> activeWorkout() async {
    final result = await _client.query(QueryOptions(
      document: gql('query ActiveWorkout { activeWorkout { $_workoutFields } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final data = result.data!['activeWorkout'] as Map<String, dynamic>?;
    return data == null ? null : Workout.fromJson(data);
  }

  Future<Workout> startWorkout({String? templateId}) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation StartWorkout(\$templateId: UUID) {
          startWorkout(templateId: \$templateId) { $_workoutFields }
        }
      '''),
      variables: {'templateId': templateId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return Workout.fromJson(result.data!['startWorkout'] as Map<String, dynamic>);
  }

  Future<LogSetResult> logSet({
    required String workoutId,
    required String exerciseId,
    required int reps,
    required double weightKg,
    double? rpe,
    bool isWarmup = false,
  }) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation LogSet(\$workoutId: UUID!, \$exerciseId: UUID!, \$reps: Int!, \$weightKg: Float!, \$rpe: Float, \$isWarmup: Boolean) {
          logSet(workoutId: \$workoutId, exerciseId: \$exerciseId, reps: \$reps, weightKg: \$weightKg, rpe: \$rpe, isWarmup: \$isWarmup) {
            set { id exerciseId setNumber reps weightKg rpe isWarmup performedAt }
            newRecords { exerciseId recordType value }
          }
        }
      '''),
      variables: {
        'workoutId': workoutId,
        'exerciseId': exerciseId,
        'reps': reps,
        'weightKg': weightKg,
        'rpe': rpe,
        'isWarmup': isWarmup,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final payload = result.data!['logSet'] as Map<String, dynamic>;
    final newRecords = (payload['newRecords'] as List<dynamic>)
        .map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>))
        .toList();
    return LogSetResult(set: WorkoutSet.fromJson(payload['set'] as Map<String, dynamic>), newRecords: newRecords);
  }

  /// Fetches the most recent set logged for this exercise (any workout), to
  /// pre-fill the log-set form with what the user did last time — the
  /// single biggest speed win for logging sets in the gym.
  Future<WorkoutSet?> lastSetForExercise(String exerciseId) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query LastSetForExercise(\$exerciseId: UUID!) {
          lastSetForExercise(exerciseId: \$exerciseId) { id exerciseId setNumber reps weightKg rpe isWarmup performedAt }
        }
      '''),
      variables: {'exerciseId': exerciseId},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final data = result.data!['lastSetForExercise'] as Map<String, dynamic>?;
    return data == null ? null : WorkoutSet.fromJson(data);
  }

  Future<Workout> finishWorkout({required String workoutId, String? notes}) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation FinishWorkout(\$workoutId: UUID!, \$notes: String) {
          finishWorkout(workoutId: \$workoutId, notes: \$notes) { $_workoutFields }
        }
      '''),
      variables: {'workoutId': workoutId, 'notes': notes},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return Workout.fromJson(result.data!['finishWorkout'] as Map<String, dynamic>);
  }

  Future<WorkoutHistoryPage> workoutHistory({int first = 20, String? after}) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query WorkoutHistory(\$first: Int!, \$after: String) {
          workoutHistory(first: \$first, after: \$after) {
            edges { cursor node { $_workoutFields } }
            pageInfo { hasNextPage endCursor }
          }
        }
      '''),
      variables: {'first': first, 'after': after},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final connection = result.data!['workoutHistory'] as Map<String, dynamic>;
    final edges = connection['edges'] as List<dynamic>;
    final pageInfo = connection['pageInfo'] as Map<String, dynamic>;
    return WorkoutHistoryPage(
      workouts: edges.map((e) => Workout.fromJson((e as Map<String, dynamic>)['node'] as Map<String, dynamic>)).toList(),
      hasNextPage: pageInfo['hasNextPage'] as bool,
      endCursor: pageInfo['endCursor'] as String?,
    );
  }

  Future<List<PersonalRecord>> personalRecords() async {
    final result = await _client.query(QueryOptions(
      document: gql('query PersonalRecords { personalRecords { exerciseId recordType value } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['personalRecords'] as List<dynamic>;
    return list.map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>)).toList();
  }
}
