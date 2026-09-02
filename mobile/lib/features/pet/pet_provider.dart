import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/app_database.dart';
import '../../core/offline/offline_provider.dart';
import '../auth/auth_provider.dart';
import 'pet_models.dart';
import 'pet_repository.dart';

final petRepositoryProvider = Provider<PetRepository>((ref) {
  // The offline snapshot cache is native-only (see offlineQueueSupported).
  final db = offlineQueueSupported ? ref.watch(appDatabaseProvider) : null;
  return PetRepository(ref.watch(graphQLClientProvider), db);
});

int _localTzOffsetMinutes() => DateTime.now().timeZoneOffset.inMinutes;

/// The caller's pet, or null when they haven't created one yet (the pet home
/// screen shows onboarding in that case). Refetched on demand — after a
/// workout finishes and when the app resumes — since mood, streak and
/// unlocks are all recomputed server-side on read.
final petProvider = AsyncNotifierProvider<PetNotifier, Pet?>(PetNotifier.new);

class PetNotifier extends AsyncNotifier<Pet?> {
  PetRepository get _repo => ref.read(petRepositoryProvider);

  @override
  Future<Pet?> build() async {
    return _repo.myPet(tzOffsetMinutes: _localTzOffsetMinutes());
  }

  /// Re-reads the pet from the server, keeping the current value visible
  /// while the request is in flight.
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => _repo.myPet(tzOffsetMinutes: _localTzOffsetMinutes()),
    );
  }

  Future<Pet> createPet({
    required String name,
    required PetSpecies species,
    required PetColor color,
  }) async {
    final pet = await _repo.createPet(name: name, species: species, color: color);
    state = AsyncData(pet);
    return pet;
  }

  Future<void> rename(String name) async {
    state = AsyncData(await _repo.renamePet(name));
  }

  Future<void> setColor(PetColor color) async {
    state = AsyncData(await _repo.setColor(color));
  }

  Future<void> equip(String accessoryId) async {
    state = AsyncData(await _repo.equipAccessory(accessoryId));
  }

  Future<void> unequip(String accessoryId) async {
    state = AsyncData(await _repo.unequipAccessory(accessoryId));
  }
}
