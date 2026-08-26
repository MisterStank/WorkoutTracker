import 'package:graphql_flutter/graphql_flutter.dart';

import 'workout_models.dart';

/// Thin wrapper around the generated GraphQL operations for workout
/// tracking, mirroring AuthRepository's shape.
class WorkoutRepository {
  WorkoutRepository(this._client);

  final GraphQLClient _client;

  static const _workoutFields = '''
    id startedAt endedAt notes status templateId
    sets { id exerciseId setNumber reps weightKg rpe setType supersetId performedAt }
  ''';

  /// Streams every set logged to this workout in real time (GraphQL
  /// subscription over WebSocket, backed by Redis pub/sub server-side) —
  /// used so a second device/tab watching the same workout updates live.
  Stream<LogSetResult> watchWorkoutProgress(String workoutId) {
    final stream = _client.subscribe(SubscriptionOptions(
      document: gql('''
        subscription WorkoutProgressUpdated(\$workoutId: UUID!) {
          workoutProgressUpdated(workoutId: \$workoutId) {
            set { id exerciseId setNumber reps weightKg rpe setType supersetId performedAt }
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
          exercises(search: \$search) { id name category instructions }
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
    SetType setType = SetType.normal,
    String? supersetId,
  }) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation LogSet(\$workoutId: UUID!, \$exerciseId: UUID!, \$reps: Int!, \$weightKg: Float!, \$rpe: Float, \$setType: SetType, \$supersetId: UUID) {
          logSet(workoutId: \$workoutId, exerciseId: \$exerciseId, reps: \$reps, weightKg: \$weightKg, rpe: \$rpe, setType: \$setType, supersetId: \$supersetId) {
            set { id exerciseId setNumber reps weightKg rpe setType supersetId performedAt }
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
        'setType': setType.graphQLValue,
        'supersetId': supersetId,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final payload = result.data!['logSet'] as Map<String, dynamic>;
    final newRecords = (payload['newRecords'] as List<dynamic>)
        .map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>))
        .toList();
    return LogSetResult(set: WorkoutSet.fromJson(payload['set'] as Map<String, dynamic>), newRecords: newRecords);
  }

  /// Corrects a mis-logged set's reps/weight/RPE/type after the fact.
  Future<WorkoutSet> updateSet({
    required String setId,
    required int reps,
    required double weightKg,
    double? rpe,
    SetType setType = SetType.normal,
  }) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation UpdateSet(\$setId: UUID!, \$reps: Int!, \$weightKg: Float!, \$rpe: Float, \$setType: SetType) {
          updateSet(setId: \$setId, reps: \$reps, weightKg: \$weightKg, rpe: \$rpe, setType: \$setType) {
            id exerciseId setNumber reps weightKg rpe setType supersetId performedAt
          }
        }
      '''),
      variables: {
        'setId': setId,
        'reps': reps,
        'weightKg': weightKg,
        'rpe': rpe,
        'setType': setType.graphQLValue,
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return WorkoutSet.fromJson(result.data!['updateSet'] as Map<String, dynamic>);
  }

  Future<void> deleteSet(String setId) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation DeleteSet(\$setId: UUID!) {
          deleteSet(setId: \$setId)
        }
      '''),
      variables: {'setId': setId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
  }

  Future<void> deleteWorkout(String workoutId) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation DeleteWorkout(\$workoutId: UUID!) {
          deleteWorkout(workoutId: \$workoutId)
        }
      '''),
      variables: {'workoutId': workoutId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
  }

  /// Fetches the most recent set logged for this exercise (any workout), to
  /// pre-fill the log-set form with what the user did last time — the
  /// single biggest speed win for logging sets in the gym.
  Future<WorkoutSet?> lastSetForExercise(String exerciseId) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query LastSetForExercise(\$exerciseId: UUID!) {
          lastSetForExercise(exerciseId: \$exerciseId) { id exerciseId setNumber reps weightKg rpe setType supersetId performedAt }
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

  /// RPE-based autoregulation: what to lift next time based on how hard the
  /// last set felt, not just what it weighed. Null if there's no prior set
  /// to base a suggestion on.
  Future<ProgressionSuggestion?> progressionSuggestion(String exerciseId) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query ProgressionSuggestion(\$exerciseId: UUID!) {
          progressionSuggestion(exerciseId: \$exerciseId) { suggestedWeightKg suggestedReps reasoning basedOnRpe }
        }
      '''),
      variables: {'exerciseId': exerciseId},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final data = result.data!['progressionSuggestion'] as Map<String, dynamic>?;
    return data == null ? null : ProgressionSuggestion.fromJson(data);
  }

  Future<PlateauStatus> plateauStatus(String exerciseId) async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query PlateauStatus(\$exerciseId: UUID!) {
          plateauStatus(exerciseId: \$exerciseId) { isPlateaued currentBestKg message }
        }
      '''),
      variables: {'exerciseId': exerciseId},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return PlateauStatus.fromJson(result.data!['plateauStatus'] as Map<String, dynamic>);
  }
}
