class TemplateExercise {
  const TemplateExercise({
    required this.id,
    required this.exerciseId,
    required this.position,
    required this.targetSets,
    this.targetReps,
  });

  final String id;
  final String exerciseId;
  final int position;
  final int targetSets;
  final int? targetReps;

  factory TemplateExercise.fromJson(Map<String, dynamic> json) => TemplateExercise(
        id: json['id'] as String,
        exerciseId: json['exerciseId'] as String,
        position: json['position'] as int,
        targetSets: json['targetSets'] as int,
        targetReps: json['targetReps'] as int?,
      );
}

class WorkoutTemplate {
  const WorkoutTemplate({required this.id, required this.name, required this.createdAt, required this.exercises});

  final String id;
  final String name;
  final DateTime createdAt;
  final List<TemplateExercise> exercises;

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) => WorkoutTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        exercises: (json['exercises'] as List<dynamic>)
            .map((e) => TemplateExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Input for creating one planned exercise within a new template.
class TemplateExerciseDraft {
  const TemplateExerciseDraft({required this.exerciseId, required this.exerciseName, required this.targetSets, this.targetReps});

  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int? targetReps;
}
