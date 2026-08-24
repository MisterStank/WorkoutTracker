class Exercise {
  const Exercise({required this.id, required this.name, required this.category});

  final String id;
  final String name;
  final String category;

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
      );
}

class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.weightKg,
    this.rpe,
    this.isWarmup = false,
    this.isPending = false,
  });

  final String id;
  final String exerciseId;
  final int setNumber;
  final int reps;
  final double weightKg;
  final double? rpe;
  final bool isWarmup;
  // True for a set logged while offline, not yet confirmed by the server —
  // never comes from the API itself (always false when parsed from JSON),
  // only set locally by ActiveWorkoutNotifier's optimistic offline path.
  final bool isPending;

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        id: json['id'] as String,
        exerciseId: json['exerciseId'] as String,
        setNumber: json['setNumber'] as int,
        reps: json['reps'] as int,
        weightKg: (json['weightKg'] as num).toDouble(),
        rpe: (json['rpe'] as num?)?.toDouble(),
        isWarmup: json['isWarmup'] as bool? ?? false,
      );
}

class Workout {
  const Workout({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.notes,
    required this.sets,
    this.templateId,
  });

  final String id;
  final DateTime startedAt;
  final String status; // "IN_PROGRESS" | "COMPLETED"
  final String notes;
  final List<WorkoutSet> sets;
  final String? templateId;

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        status: json['status'] as String,
        notes: json['notes'] as String,
        templateId: json['templateId'] as String?,
        sets: (json['sets'] as List<dynamic>)
            .map((s) => WorkoutSet.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class PersonalRecord {
  const PersonalRecord({required this.exerciseId, required this.recordType, required this.value});

  final String exerciseId;
  final String recordType;
  final double value;

  factory PersonalRecord.fromJson(Map<String, dynamic> json) => PersonalRecord(
        exerciseId: json['exerciseId'] as String,
        recordType: json['recordType'] as String,
        value: (json['value'] as num).toDouble(),
      );
}

class LogSetResult {
  const LogSetResult({required this.set, required this.newRecords});

  final WorkoutSet set;
  final List<PersonalRecord> newRecords;
}

class WorkoutHistoryPage {
  const WorkoutHistoryPage({required this.workouts, required this.hasNextPage, this.endCursor});

  final List<Workout> workouts;
  final bool hasNextPage;
  final String? endCursor;
}
