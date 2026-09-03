import 'dart:convert';

import 'package:graphql_flutter/graphql_flutter.dart';

import '../../core/graphql/graphql_errors.dart';
import '../../core/offline/app_database.dart';
import 'pet_models.dart';

/// Thin wrapper around the pet GraphQL operations, mirroring
/// AnalyticsRepository's shape. Every call returns the full [Pet] view.
///
/// [_db], when non-null (native platforms only — see [offlineQueueSupported]),
/// caches the last successful [myPet] response so the pet home screen can
/// render offline. It is a pure read-through cache; the server recomputes
/// mood/streak/unlocks on every online read.
class PetRepository {
  PetRepository(this._client, [this._db]);

  final GraphQLClient _client;
  final AppDatabase? _db;

  /// Returns null when the user has no pet yet (onboarding needed). Falls
  /// back to the cached snapshot if the request fails and one exists.
  Future<Pet?> myPet({required int tzOffsetMinutes}) async {
    final QueryResult result;
    try {
      result = await _client.query(QueryOptions(
        document: gql('''
          query MyPet(\$tz: Int) {
            pet(tzOffsetMinutes: \$tz) { $petSelection }
          }
        '''),
        variables: {'tz': tzOffsetMinutes},
        fetchPolicy: FetchPolicy.networkOnly,
      ));
    } catch (_) {
      return await _cachedPet() ?? (throw graphQLException(null));
    }
    if (result.hasException) {
      final cached = await _cachedPet();
      if (cached != null) return cached;
      throw graphQLException(result.exception);
    }
    final data = result.data?['pet'];
    if (data == null) {
      await _db?.clearPetSnapshot();
      return null;
    }
    await _db?.savePetSnapshot(jsonEncode(data));
    return Pet.fromJson(data as Map<String, dynamic>);
  }

  Future<Pet?> _cachedPet() async {
    final raw = await _db?.readPetSnapshot();
    if (raw == null) return null;
    return Pet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<Pet> createPet({
    required String name,
    required PetSpecies species,
    required PetColor color,
  }) =>
      _mutate('''
        mutation CreatePet(\$name: String!, \$species: PetSpecies!, \$color: PetColor!) {
          createPet(name: \$name, species: \$species, color: \$color) { $petSelection }
        }
      ''', {'name': name, 'species': enumToGql(species), 'color': enumToGql(color)}, 'createPet');

  Future<Pet> renamePet(String name) => _mutate('''
        mutation RenamePet(\$name: String!) {
          renamePet(name: \$name) { $petSelection }
        }
      ''', {'name': name}, 'renamePet');

  Future<Pet> setColor(PetColor color) => _mutate('''
        mutation SetPetColor(\$color: PetColor!) {
          setPetColor(color: \$color) { $petSelection }
        }
      ''', {'color': enumToGql(color)}, 'setPetColor');

  Future<Pet> equipAccessory(String accessoryId) => _mutate('''
        mutation EquipAccessory(\$id: UUID!) {
          equipAccessory(accessoryId: \$id) { $petSelection }
        }
      ''', {'id': accessoryId}, 'equipAccessory');

  Future<Pet> unequipAccessory(String accessoryId) => _mutate('''
        mutation UnequipAccessory(\$id: UUID!) {
          unequipAccessory(accessoryId: \$id) { $petSelection }
        }
      ''', {'id': accessoryId}, 'unequipAccessory');

  Future<Pet> _mutate(String doc, Map<String, dynamic> variables, String field) async {
    final result = await _client.mutate(MutationOptions(document: gql(doc), variables: variables));
    if (result.hasException) throw graphQLException(result.exception);
    final data = result.data![field] as Map<String, dynamic>;
    await _db?.savePetSnapshot(jsonEncode(data));
    return Pet.fromJson(data);
  }
}
