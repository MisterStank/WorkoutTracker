import 'package:graphql_flutter/graphql_flutter.dart';

import 'fitness_profile_models.dart';

class FitnessProfileRepository {
  FitnessProfileRepository(this._client);

  final GraphQLClient _client;

  static const _programFields = '''
    id name goal daysPerWeek notes createdAt
    days {
      id dayLabel position
      template {
        id name createdAt
        exercises { id exerciseId position targetSets targetReps supersetGroup }
      }
    }
  ''';

  Future<UserFitnessProfile?> myFitnessProfile() async {
    final result = await _client.query(QueryOptions(
      document: gql('query MyFitnessProfile { myFitnessProfile { goal experienceLevel daysPerWeek equipmentAccess avoidMuscleGroups } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final data = result.data!['myFitnessProfile'] as Map<String, dynamic>?;
    return data == null ? null : UserFitnessProfile.fromJson(data);
  }

  Future<UserFitnessProfile> saveFitnessProfile({
    required FitnessGoal goal,
    required ExperienceLevel experienceLevel,
    required int daysPerWeek,
    required List<String> equipmentAccess,
    required List<String> avoidMuscleGroups,
  }) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation SaveFitnessProfile(\$input: FitnessProfileInput!) {
          saveFitnessProfile(input: \$input) { goal experienceLevel daysPerWeek equipmentAccess avoidMuscleGroups }
        }
      '''),
      variables: {
        'input': {
          'goal': goal.graphQLValue,
          'experienceLevel': experienceLevel.graphQLValue,
          'daysPerWeek': daysPerWeek,
          'equipmentAccess': equipmentAccess,
          'avoidMuscleGroups': avoidMuscleGroups,
        },
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return UserFitnessProfile.fromJson(result.data!['saveFitnessProfile'] as Map<String, dynamic>);
  }

  Future<Program> generateProgram() async {
    final result = await _client.mutate(MutationOptions(
      document: gql('mutation GenerateProgram { generateProgram { $_programFields } }'),
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return Program.fromJson(result.data!['generateProgram'] as Map<String, dynamic>);
  }

  Future<List<Program>> myPrograms() async {
    final result = await _client.query(QueryOptions(
      document: gql('query MyPrograms { myPrograms { $_programFields } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['myPrograms'] as List<dynamic>;
    return list.map((p) => Program.fromJson(p as Map<String, dynamic>)).toList();
  }
}
