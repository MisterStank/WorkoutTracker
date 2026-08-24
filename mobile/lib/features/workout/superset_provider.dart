import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  int _counter = 0;

  /// Groups [exerciseIds] (2 or more) together under a fresh superset id.
  void group(List<String> exerciseIds) {
    if (exerciseIds.length < 2) return;
    final supersetId = 'adhoc-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
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
