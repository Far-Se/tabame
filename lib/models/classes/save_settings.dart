import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../win32/win_utils.dart';

class SaveSettings {
  SaveSettings._(this._preferenceCache);

  static const String _prefix = 'flutter.';

  /// When true, setters update the in-memory cache but skip the disk write.
  /// Set around [Boxes.reloadSettings] so a live reload never writes settings.json —
  /// two processes rewriting the whole file at once can clobber each other's data.
  static bool suppressWrites = false;

  static Completer<SaveSettings>? _completer;
  static SavedStore store = SavedStore();
  static SavedStore get _store => store;

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
    if (suppressWrites) return Future<bool>.value(true); // keep the in-memory value, skip the disk write
    return _store.setValue(valueType, prefixedKey, value);
  }

  Future<bool> clear() {
    _preferenceCache.clear();
    return _store.clear();
  }

  /// Writes all in-memory preferences after a deferred first-run setup.
  Future<bool> save() {
    final Map<String, Object> persistedPreferences = <String, Object>{
      for (final MapEntry<String, Object> entry in _preferenceCache.entries) '$_prefix${entry.key}': entry.value,
    };
    return _store._writePreferences(persistedPreferences);
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
      // Older/deferred first-run builds could write unprefixed keys. Read them
      // as normal preferences so that the next explicit save migrates them.
      final String preferenceKey = key.startsWith(_prefix) ? key.substring(_prefix.length) : key;
      preferencesMap[preferenceKey] = fromSystem[key]!;
    }
    return preferencesMap;
  }
}

class SavedStore {
  Map<String, Object>? _cachedPreferences;
  File? _localDataFilePath;
  String? _fileName;
  String get fileName {
    _fileName ??= "${WinUtils.getTabameAppDataFolder(settings: true)}\\settings.json";
    return _fileName!;
  }

  // Cross-process reload signaling. Only the Interface process sets [signalOnWrite]
  // (see AppStartup.parseArguments); it bumps a small marker file after every disk
  // write so the running QuickMenu process can watch it and live-reload. The
  // QuickMenu itself never sets the flag, so its own frequent writes don't self-trigger.
  static bool signalOnWrite = false;
  Timer? _signalTimer;
  String get reloadSignalPath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\reload.signal";

  void _bumpReloadSignal() {
    if (!signalOnWrite) return;
    // Throttle bursts (e.g. slider drags) to at most one marker write per 150ms.
    _signalTimer ??= Timer(const Duration(milliseconds: 150), () {
      _signalTimer = null;
      try {
        File(reloadSignalPath).writeAsStringSync(DateTime.now().microsecondsSinceEpoch.toString());
      } catch (_) {}
    });
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
      final String stringMap = _safeRead(localDataFile);
      Map<String, Object>? parsed = _tryDecode(stringMap);
      if (parsed != null) {
        preferences = parsed;
        // Refresh the backup only with content we know is valid and complete.
        try {
          File("$fileName.bk").writeAsStringSync(stringMap);
        } catch (_) {}
      } else {
        // settings.json was empty or partial (e.g. read while another process was
        // mid non-atomic write). Recover from the last-known-good backup instead of
        // dropping keys, and do NOT overwrite the backup with the bad content.
        final File backup = File("$fileName.bk");
        if (backup.existsSync()) {
          parsed = _tryDecode(_safeRead(backup));
          if (parsed != null) preferences = parsed;
        }
      }
    }
    _cachedPreferences = preferences;
    return preferences;
  }

  String _safeRead(File file) {
    try {
      return file.readAsStringSync();
    } catch (_) {
      return "";
    }
  }

  Map<String, Object>? _tryDecode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final Object? data = json.decode(raw);
      if (data is Map) return data.cast<String, Object>();
    } catch (_) {}
    return null;
  }

  Future<bool> _writePreferences(Map<String, Object> preferences) async {
    if (SaveSettings.suppressWrites) return true;
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
    _bumpReloadSignal();
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
