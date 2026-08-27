import 'package:graphql_flutter/graphql_flutter.dart';
import '../../core/graphql/graphql_errors.dart';

import 'fitness_profile_models.dart';

class FitnessProfileRepository {
  FitnessProfileRepository(this._client);

  final GraphQLClient _client;

  static const _programFields = '''
    id name goal daysPerWeek notes createdAt isActive progressionRule
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
    if (result.hasException) throw graphQLException(result.exception);
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
    if (result.hasException) throw graphQLException(result.exception);
    return UserFitnessProfile.fromJson(result.data!['saveFitnessProfile'] as Map<String, dynamic>);
  }

  Future<Program> generateProgram() async {
    final result = await _client.mutate(MutationOptions(
      document: gql('mutation GenerateProgram { generateProgram { $_programFields } }'),
    ));
    if (result.hasException) throw graphQLException(result.exception);
    return Program.fromJson(result.data!['generateProgram'] as Map<String, dynamic>);
  }

  Future<List<Program>> myPrograms() async {
    final result = await _client.query(QueryOptions(
      document: gql('query MyPrograms { myPrograms { $_programFields } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw graphQLException(result.exception);
    final list = result.data!['myPrograms'] as List<dynamic>;
    return list.map((p) => Program.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<NextWorkout?> nextWorkout() async {
    final result = await _client.query(QueryOptions(
      document: gql('query NextWorkout { nextWorkout { weekNumber program { $_programFields } day { id dayLabel position template { id name createdAt exercises { id exerciseId position targetSets targetReps supersetGroup } } } } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw graphQLException(result.exception);
    final data = result.data!['nextWorkout'] as Map<String, dynamic>?;
    return data == null ? null : NextWorkout.fromJson(data);
  }

  Future<List<ExerciseTarget>> programDayTargets(String programDayId) async {
    final result = await _client.query(QueryOptions(
      document: gql('query ProgramDayTargets(\$id: UUID!) { programDayTargets(programDayId: \$id) { exerciseId targetSets targetReps suggestedWeightKg weekNumber reasoning } }'),
      variables: {'id': programDayId},
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw graphQLException(result.exception);
    final list = result.data!['programDayTargets'] as List<dynamic>;
    return list.map((t) => ExerciseTarget.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<Program> createProgramFromTemplates(String name, List<(String dayLabel, String templateId)> days) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation CreateProgramFromTemplates(\$input: CreateProgramInput!) {
          createProgramFromTemplates(input: \$input) { $_programFields }
        }
      '''),
      variables: {
        'input': {
          'name': name,
          'days': [
            for (final (dayLabel, templateId) in days) {'dayLabel': dayLabel, 'templateId': templateId},
          ],
        },
      },
    ));
    if (result.hasException) throw graphQLException(result.exception);
    return Program.fromJson(result.data!['createProgramFromTemplates'] as Map<String, dynamic>);
  }

  Future<Program> setActiveProgram(String programId) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation SetActiveProgram(\$programId: UUID!) {
          setActiveProgram(programId: \$programId) { $_programFields }
        }
      '''),
      variables: {'programId': programId},
    ));
    if (result.hasException) throw graphQLException(result.exception);
    return Program.fromJson(result.data!['setActiveProgram'] as Map<String, dynamic>);
  }
}
