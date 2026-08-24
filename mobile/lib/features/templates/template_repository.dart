import 'package:graphql_flutter/graphql_flutter.dart';

import 'template_models.dart';

class TemplateRepository {
  TemplateRepository(this._client);

  final GraphQLClient _client;

  static const _templateFields = '''
    id name createdAt
    exercises { id exerciseId position targetSets targetReps supersetGroup }
  ''';

  Future<List<WorkoutTemplate>> list() async {
    final result = await _client.query(QueryOptions(
      document: gql('query WorkoutTemplates { workoutTemplates { $_templateFields } }'),
      fetchPolicy: FetchPolicy.networkOnly,
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    final list = result.data!['workoutTemplates'] as List<dynamic>;
    return list.map((t) => WorkoutTemplate.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<WorkoutTemplate> create({required String name, required List<TemplateExerciseDraft> exercises}) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        mutation CreateWorkoutTemplate(\$name: String!, \$exercises: [TemplateExerciseInput!]!) {
          createWorkoutTemplate(name: \$name, exercises: \$exercises) { $_templateFields }
        }
      '''),
      variables: {
        'name': name,
        'exercises': exercises
            .map((e) => {
                  'exerciseId': e.exerciseId,
                  'targetSets': e.targetSets,
                  'targetReps': e.targetReps,
                  'supersetGroup': e.supersetGroup,
                })
            .toList(),
      },
    ));
    if (result.hasException) throw Exception(result.exception.toString());
    return WorkoutTemplate.fromJson(result.data!['createWorkoutTemplate'] as Map<String, dynamic>);
  }

  Future<void> delete(String templateId) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('mutation DeleteWorkoutTemplate(\$templateId: UUID!) { deleteWorkoutTemplate(templateId: \$templateId) }'),
      variables: {'templateId': templateId},
    ));
    if (result.hasException) throw Exception(result.exception.toString());
  }
}
