import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Tracks which exercises are currently grouped as an ad-hoc superset
/// during a blank (non-template) workout: exerciseId -> supersetId. Purely
/// client-side session state — reset whenever a workout starts or finishes,
/// since a superset pairing only makes sense within one session. Grouping
/// planned in advance via a template's supersetGroup is handled separately;
/// this covers "decide mid-workout that these two exercises should
/// alternate."
final activeSupersetsProvider = StateNotifierProvider<ActiveSupersetsNotifier, Map<String, String>>((ref) {
  return ActiveSupersetsNotifier();
});

class ActiveSupersetsNotifier extends StateNotifier<Map<String, String>> {
  ActiveSupersetsNotifier() : super(const {});

  static const _uuid = Uuid();

  /// Groups [exerciseIds] (2 or more) together under a fresh superset id.
  /// Must be a real UUID, not just a locally-unique string — this id is
  /// sent as-is to logSet's supersetId: UUID! GraphQL argument.
  void group(List<String> exerciseIds) {
    if (exerciseIds.length < 2) return;
    final supersetId = _uuid.v4();
    state = {
      ...state,
      for (final id in exerciseIds) id: supersetId,
    };
  }

  void ungroup(String exerciseId) {
    if (!state.containsKey(exerciseId)) return;
    final next = {...state}..remove(exerciseId);
    state = next;
  }

  void reset() => state = const {};

  String? supersetIdFor(String exerciseId) => state[exerciseId];
}
