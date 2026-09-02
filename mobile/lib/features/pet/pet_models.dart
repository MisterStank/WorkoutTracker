// Client-side view of the virtual companion. Mood, streak and stage are all
// computed by the server on read (see internal/service/pet_rules.go); the
// client only renders them.

enum PetSpecies { sprout, ember, pebble, drift }

enum PetColor { green, red, blue, amber, violet }

enum PetStage { egg, hatchling, juvenile, adult, champion }

enum MoodState { happy, content, low, neglected }

T _enumFromGql<T extends Enum>(List<T> values, String raw, T fallback) {
  final name = raw.toLowerCase();
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

String enumToGql(Enum v) => v.name.toUpperCase();

class Accessory {
  const Accessory({
    required this.id,
    required this.code,
    required this.name,
    required this.slot,
    required this.unlockHint,
  });

  final String id;
  final String code;
  final String name;
  final String slot;
  final String unlockHint;

  factory Accessory.fromJson(Map<String, dynamic> json) => Accessory(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        slot: json['slot'] as String,
        unlockHint: json['unlockHint'] as String? ?? '',
      );
}

class PetAccessory {
  const PetAccessory({required this.accessory, required this.unlockedAt, required this.equipped});

  final Accessory accessory;
  final DateTime unlockedAt;
  final bool equipped;

  factory PetAccessory.fromJson(Map<String, dynamic> json) => PetAccessory(
        accessory: Accessory.fromJson(json['accessory'] as Map<String, dynamic>),
        unlockedAt: DateTime.parse(json['unlockedAt'] as String),
        equipped: json['equipped'] as bool,
      );
}

class PetAppearance {
  const PetAppearance({
    required this.bodyAssetKey,
    required this.expressionAssetKey,
    required this.tint,
    required this.layers,
  });

  final String bodyAssetKey;
  final String expressionAssetKey;
  final String tint;
  final List<String> layers;

  factory PetAppearance.fromJson(Map<String, dynamic> json) => PetAppearance(
        bodyAssetKey: json['bodyAssetKey'] as String,
        expressionAssetKey: json['expressionAssetKey'] as String,
        tint: json['tint'] as String,
        layers: (json['layers'] as List<dynamic>).cast<String>(),
      );
}

class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.color,
    required this.stage,
    required this.stageLabel,
    required this.mood,
    required this.moodState,
    required this.currentStreak,
    required this.longestStreak,
    required this.workoutsToNextStage,
    required this.hatchedAt,
    required this.appearance,
    required this.accessories,
    required this.newlyUnlocked,
  });

  final String id;
  final String name;
  final PetSpecies species;
  final PetColor color;
  final PetStage stage;
  final String stageLabel;
  final int mood;
  final MoodState moodState;
  final int currentStreak;
  final int longestStreak;
  final int? workoutsToNextStage;
  final DateTime? hatchedAt;
  final PetAppearance appearance;
  final List<PetAccessory> accessories;
  final List<PetAccessory> newlyUnlocked;

  bool get isNeglected => moodState == MoodState.neglected;

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        id: json['id'] as String,
        name: json['name'] as String,
        species: _enumFromGql(PetSpecies.values, json['species'] as String, PetSpecies.sprout),
        color: _enumFromGql(PetColor.values, json['color'] as String, PetColor.green),
        stage: _enumFromGql(PetStage.values, json['stage'] as String, PetStage.egg),
        stageLabel: json['stageLabel'] as String,
        mood: json['mood'] as int,
        moodState: _enumFromGql(MoodState.values, json['moodState'] as String, MoodState.content),
        currentStreak: json['currentStreak'] as int,
        longestStreak: json['longestStreak'] as int,
        workoutsToNextStage: json['workoutsToNextStage'] as int?,
        hatchedAt: json['hatchedAt'] == null ? null : DateTime.parse(json['hatchedAt'] as String),
        appearance: PetAppearance.fromJson(json['appearance'] as Map<String, dynamic>),
        accessories: (json['accessories'] as List<dynamic>)
            .map((a) => PetAccessory.fromJson(a as Map<String, dynamic>))
            .toList(),
        newlyUnlocked: (json['newlyUnlocked'] as List<dynamic>? ?? [])
            .map((a) => PetAccessory.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

/// The GraphQL selection set shared by every pet query/mutation, so they all
/// return an identically-shaped [Pet].
const petSelection = '''
  id
  name
  species
  color
  stage
  stageLabel
  mood
  moodState
  currentStreak
  longestStreak
  workoutsToNextStage
  hatchedAt
  appearance { bodyAssetKey expressionAssetKey tint layers }
  accessories { accessory { id code name slot unlockHint } unlockedAt equipped }
  newlyUnlocked { accessory { id code name slot unlockHint } unlockedAt equipped }
''';
