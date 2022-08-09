import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../win32/win32.dart';

class SaveSettings {
  SaveSettings._(this._preferenceCache);

  static const String _prefix = 'flutter.';
  static Completer<SaveSettings>? _completer;
  static SavedStore store = SavedStore();
  static get _store => store;

  static Future<SaveSettings> getInstance() async {
    if (_completer == null) {
      final Completer<SaveSettings> completer = Completer<SaveSettings>();
      try {
        final Map<String, Object> preferencesMap = await _getSaveSettingsMap();
        completer.complete(SaveSettings._(preferencesMap));
      } on Exception catch (e) {
        completer.completeError(e);
        final Future<SaveSettings> sharedPrefsFuture = completer.future;
        _completer = null;
        return sharedPrefsFuture;
      }
      _completer = completer;
    }
    return _completer!.future;
  }

  final Map<String, Object> _preferenceCache;

  Set<String> getKeys() => Set<String>.from(_preferenceCache.keys);

  Object? get(String key) => _preferenceCache[key];

  bool? getBool(String key) => _preferenceCache[key] as bool?;

  int? getInt(String key) => _preferenceCache[key] as int?;

  double? getDouble(String key) => _preferenceCache[key] as double?;

  String? getString(String key) => _preferenceCache[key] as String?;

  bool containsKey(String key) => _preferenceCache.containsKey(key);

  List<String>? getStringList(String key) {
    List<dynamic>? list = _preferenceCache[key] as List<dynamic>?;
    if (list != null && list is! List<String>) {
      list = list.cast<String>().toList();
      _preferenceCache[key] = list;
    }

    return list?.toList() as List<String>?;
  }

  Future<bool> setBool(String key, bool value) => _setValue('Bool', key, value);

  Future<bool> setInt(String key, int value) => _setValue('Int', key, value);

  Future<bool> setDouble(String key, double value) => _setValue('Double', key, value);

  Future<bool> setString(String key, String value) => _setValue('String', key, value);

  Future<bool> setStringList(String key, List<String> value) => _setValue('StringList', key, value);

  Future<bool> remove(String key) {
    final String prefixedKey = '$_prefix$key';
    _preferenceCache.remove(key);
    return _store.remove(prefixedKey);
  }

  Future<bool> _setValue(String valueType, String key, Object value) {
    ArgumentError.checkNotNull(value, 'value');
    final String prefixedKey = '$_prefix$key';
    if (value is List<String>) {
      _preferenceCache[key] = value.toList();
    } else {
      _preferenceCache[key] = value;
    }
    return _store.setValue(valueType, prefixedKey, value);
  }

  Future<bool> clear() {
    _preferenceCache.clear();
    return _store.clear();
  }

  String get fileName => _store.fileName;
  Future<void> reload() async {
    _store.clearCache();
    final Map<String, Object> preferences = await SaveSettings._getSaveSettingsMap();
    _preferenceCache.clear();
    _preferenceCache.addAll(preferences);
  }

  static Future<Map<String, Object>> _getSaveSettingsMap() async {
    final Map<String, Object> fromSystem = await _store.getAll();

    final Map<String, Object> preferencesMap = <String, Object>{};
    for (final String key in fromSystem.keys) {
      assert(key.startsWith(_prefix));
      preferencesMap[key.substring(_prefix.length)] = fromSystem[key]!;
    }
    return preferencesMap;
  }
}

class SavedStore {
  Map<String, Object>? _cachedPreferences;
  File? _localDataFilePath;
  String? _fileName;
  String get fileName {
    _fileName ??= "${WinUtils.getTabameSettingsFolder()}\\saved.json";
    return _fileName!;
  }

  Future<File?> _getLocalDataFile() async {
    if (_localDataFilePath != null) {
      return _localDataFilePath!;
    }
    return _localDataFilePath = File(fileName);
  }

  void clearCache() => _cachedPreferences = null;
  Future<Map<String, Object>> _readPreferences() async {
    if (_cachedPreferences != null) {
      return _cachedPreferences!;
    }
    Map<String, Object> preferences = <String, Object>{};
    final File? localDataFile = await _getLocalDataFile();
    if (localDataFile != null && localDataFile.existsSync()) {
      final String stringMap = localDataFile.readAsStringSync();
      if (stringMap.isNotEmpty) {
        final Object? data = json.decode(stringMap);
        if (data is Map) {
          preferences = data.cast<String, Object>();
        }
      }
    }
    _cachedPreferences = preferences;
    return preferences;
  }

  Future<bool> _writePreferences(Map<String, Object> preferences) async {
    try {
      final File? localDataFile = await _getLocalDataFile();
      if (localDataFile == null) {
        return false;
      }
      if (!localDataFile.existsSync()) {
        localDataFile.createSync(recursive: true);
      }
      final String stringMap = json.encode(preferences);
      localDataFile.writeAsStringSync(stringMap);
    } catch (e) {
      return false;
    }
    return true;
  }

  Future<bool> clear() async {
    final Map<String, Object> preferences = await _readPreferences();
    preferences.clear();
    return _writePreferences(preferences);
  }

  Future<Map<String, Object>> getAll() async {
    return _readPreferences();
  }

  Future<bool> remove(String key) async {
    final Map<String, Object> preferences = await _readPreferences();
    preferences.remove(key);
    return _writePreferences(preferences);
  }

  Future<bool> setValue(String valueType, String key, Object value) async {
    final Map<String, Object> preferences = await _readPreferences();
    preferences[key] = value;
    return _writePreferences(preferences);
  }
}
