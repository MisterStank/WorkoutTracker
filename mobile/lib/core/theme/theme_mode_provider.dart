import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storageKey = 'theme_mode_preference';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(const FlutterSecureStorage());
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _storage.read(key: _storageKey).then((value) => state = _fromStorage(value));
  }

  final FlutterSecureStorage _storage;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _storageKey, value: mode.name);
  }

  static ThemeMode _fromStorage(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
