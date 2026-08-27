import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_profile_models.dart';
import 'fitness_profile_provider.dart';

/// The per-exercise weekly targets for the program day the active workout
/// was started from, keyed by exerciseId. Empty for a blank workout or one
/// started from a hand-built template not tied to a program.
///
/// Populated by [ProgramTargetsNotifier.loadForTemplate] right after
/// starting a workout, and consumed by the log-set sheet to pre-fill the
/// suggested load for each planned exercise.
final activeProgramTargetsProvider =
    StateNotifierProvider<ProgramTargetsNotifier, Map<String, ExerciseTarget>>((ref) {
  return ProgramTargetsNotifier(ref);
});

class ProgramTargetsNotifier extends StateNotifier<Map<String, ExerciseTarget>> {
  ProgramTargetsNotifier(this._ref) : super(const {});

  final Ref _ref;

  void clear() => state = const {};

  /// Looks up which program day (if any) owns [templateId] and loads that
  /// day's targets for the current week. Best-effort: any failure just
  /// leaves targets empty and the sheet falls back to last-set pre-fill.
  Future<void> loadForTemplate(String? templateId) async {
    if (templateId == null) {
      clear();
      return;
    }
    try {
      final repo = _ref.read(fitnessProfileRepositoryProvider);
      final programs = await repo.myPrograms();
      String? programDayId;
      for (final p in programs) {
        for (final d in p.days) {
          if (d.template.id == templateId) programDayId = d.id;
        }
      }
      if (programDayId == null) {
        clear();
        return;
      }
      final targets = await repo.programDayTargets(programDayId);
      state = {for (final t in targets) t.exerciseId: t};
    } catch (_) {
      clear();
    }
  }
}
