import '../templates/template_models.dart';

enum FitnessGoal {
  strength,
  hypertrophy,
  fatLoss,
  generalFitness;

  String get label => switch (this) {
        FitnessGoal.strength => 'Strength',
        FitnessGoal.hypertrophy => 'Muscle growth',
        FitnessGoal.fatLoss => 'Fat loss',
        FitnessGoal.generalFitness => 'General fitness',
      };

  String get graphQLValue => switch (this) {
        FitnessGoal.strength => 'STRENGTH',
        FitnessGoal.hypertrophy => 'HYPERTROPHY',
        FitnessGoal.fatLoss => 'FAT_LOSS',
        FitnessGoal.generalFitness => 'GENERAL_FITNESS',
      };

  static FitnessGoal fromGraphQL(String value) => switch (value) {
        'STRENGTH' => FitnessGoal.strength,
        'HYPERTROPHY' => FitnessGoal.hypertrophy,
        'FAT_LOSS' => FitnessGoal.fatLoss,
        _ => FitnessGoal.generalFitness,
      };
}

enum ExperienceLevel {
  beginner,
  intermediate,
  advanced;

  String get label => switch (this) {
        ExperienceLevel.beginner => 'Beginner',
        ExperienceLevel.intermediate => 'Intermediate',
        ExperienceLevel.advanced => 'Advanced',
      };

  String get graphQLValue => switch (this) {
        ExperienceLevel.beginner => 'BEGINNER',
        ExperienceLevel.intermediate => 'INTERMEDIATE',
        ExperienceLevel.advanced => 'ADVANCED',
      };

  static ExperienceLevel fromGraphQL(String value) => switch (value) {
        'INTERMEDIATE' => ExperienceLevel.intermediate,
        'ADVANCED' => ExperienceLevel.advanced,
        _ => ExperienceLevel.beginner,
      };
}

/// Equipment/muscle-group vocabularies the generator understands — kept in
/// sync with the exercise catalog's own tags (equipment column, muscle
/// groups array) rather than being a separate free-text list.
const availableEquipment = ['barbell', 'dumbbell', 'bodyweight', 'cable', 'machine'];
const availableMuscleGroups = ['chest', 'back', 'shoulders', 'biceps', 'triceps', 'quads', 'hamstrings', 'glutes', 'abs'];

class UserFitnessProfile {
  const UserFitnessProfile({
    required this.goal,
    required this.experienceLevel,
    required this.daysPerWeek,
    required this.equipmentAccess,
    required this.avoidMuscleGroups,
  });

  final FitnessGoal goal;
  final ExperienceLevel experienceLevel;
  final int daysPerWeek;
  final List<String> equipmentAccess;
  final List<String> avoidMuscleGroups;

  factory UserFitnessProfile.fromJson(Map<String, dynamic> json) => UserFitnessProfile(
        goal: FitnessGoal.fromGraphQL(json['goal'] as String),
        experienceLevel: ExperienceLevel.fromGraphQL(json['experienceLevel'] as String),
        daysPerWeek: json['daysPerWeek'] as int,
        equipmentAccess: (json['equipmentAccess'] as List<dynamic>).cast<String>(),
        avoidMuscleGroups: (json['avoidMuscleGroups'] as List<dynamic>).cast<String>(),
      );
}

class ProgramDay {
  const ProgramDay({required this.id, required this.dayLabel, required this.position, required this.template});

  final String id;
  final String dayLabel;
  final int position;
  final WorkoutTemplate template;

  factory ProgramDay.fromJson(Map<String, dynamic> json) => ProgramDay(
        id: json['id'] as String,
        dayLabel: json['dayLabel'] as String,
        position: json['position'] as int,
        template: WorkoutTemplate.fromJson(json['template'] as Map<String, dynamic>),
      );
}

/// How a program escalates loads week to week — derived from its goal.
enum ProgressionRule {
  linear('Linear progression', 'Add a little weight every week'),
  doubleProgression('Double progression', 'Add reps to the top of the range, then add weight'),
  none('Maintain', 'Hold your working weights');

  const ProgressionRule(this.label, this.blurb);
  final String label;
  final String blurb;

  static ProgressionRule fromGraphQL(String v) => switch (v) {
        'LINEAR' => ProgressionRule.linear,
        'DOUBLE_PROGRESSION' => ProgressionRule.doubleProgression,
        _ => ProgressionRule.none,
      };
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.goal,
    required this.daysPerWeek,
    required this.notes,
    required this.days,
    required this.createdAt,
    required this.isActive,
    this.progressionRule = ProgressionRule.none,
  });

  final String id;
  final String name;
  final FitnessGoal goal;
  final int daysPerWeek;
  final String notes;
  final List<ProgramDay> days;
  final DateTime createdAt;
  // The one program (at most) the user is currently following — drives
  // Home's "Continue" card. Set via FitnessProfileRepository.setActiveProgram.
  final bool isActive;
  final ProgressionRule progressionRule;

  factory Program.fromJson(Map<String, dynamic> json) => Program(
        id: json['id'] as String,
        name: json['name'] as String,
        goal: FitnessGoal.fromGraphQL(json['goal'] as String),
        daysPerWeek: json['daysPerWeek'] as int,
        notes: json['notes'] as String,
        days: (json['days'] as List<dynamic>).map((d) => ProgramDay.fromJson(d as Map<String, dynamic>)).toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isActive: json['isActive'] as bool,
        progressionRule: ProgressionRule.fromGraphQL(json['progressionRule'] as String? ?? 'NONE'),
      );
}

/// "What should I train next" for the user's most recent program — see
/// NextWorkout in the backend domain package for the wraparound logic.
class NextWorkout {
  const NextWorkout({required this.program, required this.day, this.weekNumber = 1});

  final Program program;
  final ProgramDay day;
  final int weekNumber;

  factory NextWorkout.fromJson(Map<String, dynamic> json) => NextWorkout(
        program: Program.fromJson(json['program'] as Map<String, dynamic>),
        day: ProgramDay.fromJson(json['day'] as Map<String, dynamic>),
        weekNumber: json['weekNumber'] as int? ?? 1,
      );
}

/// One exercise's prescription for a program day this week.
class ExerciseTarget {
  const ExerciseTarget({
    required this.exerciseId,
    required this.targetSets,
    this.targetReps,
    required this.suggestedWeightKg,
    required this.weekNumber,
    required this.reasoning,
  });

  final String exerciseId;
  final int targetSets;
  final int? targetReps;
  final double suggestedWeightKg;
  final int weekNumber;
  final String reasoning;

  factory ExerciseTarget.fromJson(Map<String, dynamic> json) => ExerciseTarget(
        exerciseId: json['exerciseId'] as String,
        targetSets: json['targetSets'] as int,
        targetReps: json['targetReps'] as int?,
        suggestedWeightKg: (json['suggestedWeightKg'] as num).toDouble(),
        weekNumber: json['weekNumber'] as int,
        reasoning: json['reasoning'] as String,
      );
}
