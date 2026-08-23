import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'weight_unit.dart';

const _storageKey = 'weight_unit_preference';

final weightUnitProvider = StateNotifierProvider<WeightUnitNotifier, WeightUnit>((ref) {
  return WeightUnitNotifier(const FlutterSecureStorage());
});

class WeightUnitNotifier extends StateNotifier<WeightUnit> {
  WeightUnitNotifier(this._storage) : super(WeightUnit.kg) {
    _storage.read(key: _storageKey).then((value) => state = WeightUnit.fromStorage(value));
  }

  final FlutterSecureStorage _storage;

  Future<void> toggle() async {
    final next = state == WeightUnit.kg ? WeightUnit.lb : WeightUnit.kg;
    state = next;
    await _storage.write(key: _storageKey, value: next.name);
  }
}
