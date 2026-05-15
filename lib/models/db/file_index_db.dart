import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../win32/win_utils.dart';

enum SearchResultEntryType {
  file,
  app,
}

class SearchResultNode {
  final int id;
  final String path;
  final String name;
  final bool isDirectory;
  final SearchResultEntryType entryType;
  final String? launchTarget;
  final String? parsingName;
  final String? appUserModelId;
  final String? subtitle;
  final String? stableIdentity;

  const SearchResultNode({
    required this.id,
    required this.path,
    required this.name,
    required this.isDirectory,
    this.entryType = SearchResultEntryType.file,
    this.launchTarget,
    this.parsingName,
    this.appUserModelId,
    this.subtitle,
    this.stableIdentity,
  });

  bool get isApp => entryType == SearchResultEntryType.app;
}

class FileIndexDb {
  FileIndexDb._();
  static final FileIndexDb instance = FileIndexDb._();
  static const String launcherAppsRootName = '__launcher_apps__';

  Database? _db;
  String? _manualPath;
  String dbName = kReleaseMode ? 'file_index.db' : 'file_index_debug.db';
  String get dbPath {
    if (_manualPath != null) return _manualPath!;
    final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
    return p.join(appDir.path, dbName);
  }

  void setDatabasePath(String path) {
    _manualPath = path;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final String path;
    if (_manualPath != null) {
      path = _manualPath!;
    } else {
      final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
      path = p.join(appDir.path, dbName);
    }

    try {
      return _openAndSetupDb(path);
    } catch (e) {
      if (e.toString().contains('malformed')) {
        debugPrint('FileIndexDb: Database is malformed, attempting to recreate...');
        await repair();
        return _openAndSetupDb(path);
      }
      rethrow;
    }
  }

  Future<void> repair() async {
    _db?.close();
    _db = null;

    final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
    final String path = p.join(appDir.path, dbName);

    final File dbFile = File(path);
    if (await dbFile.exists()) {
      try {
        await dbFile.delete();
        final File walFile = File('$path-wal');
        final File shmFile = File('$path-shm');
        if (await walFile.exists()) await walFile.delete();
        if (await shmFile.exists()) await shmFile.delete();
      } catch (e) {
        debugPrint('FileIndexDb: Error deleting files during repair: $e');
      }
    }
  }

  Database _openAndSetupDb(String dbPath) {
    if (Platform.isWindows) {
      final String exeDir = p.dirname(Platform.resolvedExecutable);
      final String dllPath = p.join(exeDir, 'sqlite3.dll');
      if (!File(dllPath).existsSync()) {
        final String fallbackDll = p.join(exeDir, 'windows', 'sqlite3.dll');
        if (File(fallbackDll).existsSync()) {
          try {
            File(fallbackDll).renameSync(dllPath);
          } catch (e) {
            debugPrint('FileIndexDb: Error moving sqlite3.dll: $e');
          }
        }
      }
    }

    final Database db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');

    db.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        is_directory INTEGER NOT NULL,
        times_opened INTEGER NOT NULL DEFAULT 0,
        is_searchable INTEGER NOT NULL DEFAULT 1,
        entry_type TEXT NOT NULL DEFAULT 'file',
        launch_target TEXT,
        parsing_name TEXT,
        app_user_model_id TEXT,
        subtitle TEXT,
        stable_identity TEXT,
        FOREIGN KEY(parent_id) REFERENCES nodes(id) ON DELETE CASCADE
      );
    ''');

    try {
      db.execute('ALTER TABLE nodes ADD COLUMN times_opened INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN is_searchable INTEGER NOT NULL DEFAULT 1;');
    } catch (_) {}
    try {
      db.execute("ALTER TABLE nodes ADD COLUMN entry_type TEXT NOT NULL DEFAULT 'file';");
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN launch_target TEXT;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN parsing_name TEXT;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN app_user_model_id TEXT;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN subtitle TEXT;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN stable_identity TEXT;');
    } catch (_) {}

    db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_parent_id ON nodes(parent_id);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_entry_type ON nodes(entry_type);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_app_user_model_id ON nodes(app_user_model_id);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_stable_identity ON nodes(stable_identity);');

    try {
      db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_nodes USING fts5(
          name,
          content='nodes',
          content_rowid='id',
          tokenize="trigram"
        );
      ''');

      db.execute('DROP TRIGGER IF EXISTS nodes_ai;');
      db.execute('''
        CREATE TRIGGER nodes_ai AFTER INSERT ON nodes
        WHEN new.is_searchable = 1
        BEGIN
          INSERT INTO fts_nodes(rowid, name) VALUES (new.id, new.name);
        END;
      ''');

      db.execute('DROP TRIGGER IF EXISTS nodes_ad;');
      db.execute('''
        CREATE TRIGGER nodes_ad AFTER DELETE ON nodes BEGIN
          INSERT INTO fts_nodes(fts_nodes, rowid, name) VALUES('delete', old.id, old.name);
        END;
      ''');

      db.execute('DROP TRIGGER IF EXISTS nodes_au;');
      db.execute('''
        CREATE TRIGGER nodes_au AFTER UPDATE ON nodes BEGIN
          INSERT INTO fts_nodes(fts_nodes, rowid, name) VALUES('delete', old.id, old.name);
          INSERT INTO fts_nodes(rowid, name)
          SELECT new.id, new.name WHERE new.is_searchable = 1;
        END;
      ''');
    } catch (e) {
      debugPrint('FTS5 Trigram not supported: $e');
    }

    return db;
  }

  int getDescendantCount(String path) {
    final Database? db = _db;
    if (db == null) return 0;

    final int? rootId = findNode(null, path);
    if (rootId == null) return 0;

    final ResultSet results = db.select('''
      WITH RECURSIVE descendants AS (
        SELECT id FROM nodes WHERE parent_id = ?
        UNION ALL
        SELECT n.id FROM nodes n
        JOIN descendants d ON n.parent_id = d.id
      )
      SELECT count(*) as total FROM descendants;
    ''', <Object?>[rootId]);

    return results.first['total'] as int;
  }

  String? getAbsolutePath(int nodeId) {
    final Database? db = _db;
    if (db == null) return null;

    final ResultSet results = db.select('''
      WITH RECURSIVE path_cte(id, parent_id, name, full_path) AS (
        SELECT id, parent_id, name, name
        FROM nodes
        WHERE id = ?
        UNION ALL
        SELECT p.id, p.parent_id, p.name,
               p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path
        FROM nodes p
        JOIN path_cte c ON c.parent_id = p.id
      )
      SELECT full_path FROM path_cte WHERE parent_id IS NULL;
    ''', <Object?>[nodeId]);

    if (results.isEmpty) return null;
    return results.first['full_path'] as String;
  }

  int insertNode(
    int? parentId,
    String name,
    bool isDirectory, {
    bool isSearchable = true,
    SearchResultEntryType entryType = SearchResultEntryType.file,
    String? launchTarget,
    String? parsingName,
    String? appUserModelId,
    String? subtitle,
    String? stableIdentity,
    int timesOpened = 0,
  }) {
    final Database? db = _db;
    if (db == null) throw StateError('FileIndexDb: Database not initialized');
    final PreparedStatement stmt = db.prepare('''
      INSERT INTO nodes (
        parent_id, name, is_directory, times_opened, is_searchable,
        entry_type, launch_target, parsing_name, app_user_model_id, subtitle, stable_identity
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    stmt.execute(<Object?>[
      parentId,
      name,
      isDirectory ? 1 : 0,
      timesOpened,
      isSearchable ? 1 : 0,
      _entryTypeToDbValue(entryType),
      launchTarget,
      parsingName,
      appUserModelId,
      subtitle,
      stableIdentity,
    ]);
    final int id = db.lastInsertRowId;
    stmt.close();
    return id;
  }

  int insertAppNode(
    int parentId, {
    required String name,
    required String launchTarget,
    required String parsingName,
    required String appUserModelId,
    required String subtitle,
    required String stableIdentity,
    int timesOpened = 0,
  }) {
    return insertNode(
      parentId,
      name,
      false,
      isSearchable: true,
      entryType: SearchResultEntryType.app,
      launchTarget: launchTarget,
      parsingName: parsingName,
      appUserModelId: appUserModelId,
      subtitle: subtitle,
      stableIdentity: stableIdentity,
      timesOpened: timesOpened,
    );
  }

  void updateAppNode({
    required int id,
    required int parentId,
    required String name,
    required String launchTarget,
    required String parsingName,
    required String appUserModelId,
    required String subtitle,
    required String stableIdentity,
  }) {
    _db?.execute('''
      UPDATE nodes
      SET parent_id = ?,
          name = ?,
          is_directory = 0,
          is_searchable = 1,
          entry_type = 'app',
          launch_target = ?,
          parsing_name = ?,
          app_user_model_id = ?,
          subtitle = ?,
          stable_identity = ?
      WHERE id = ?
    ''', <Object?>[
      parentId,
      name,
      launchTarget,
      parsingName,
      appUserModelId,
      subtitle,
      stableIdentity,
      id,
    ]);
  }

  void incrementTimesOpened(int id) {
    _db?.execute('UPDATE nodes SET times_opened = times_opened + 1 WHERE id = ?', <Object?>[id]);
  }

  void deleteNode(int id) {
    _db?.execute('DELETE FROM nodes WHERE id = ?', <Object?>[id]);
  }

  void deleteChildren(int parentId) {
    _db?.execute('DELETE FROM nodes WHERE parent_id = ?', <Object?>[parentId]);
  }

  void deleteRootsByEntryType(SearchResultEntryType entryType) {
    _db?.execute(
      'DELETE FROM nodes WHERE parent_id IS NULL AND entry_type = ?',
      <Object?>[_entryTypeToDbValue(entryType)],
    );
  }

  int upsertNode(int? parentId, String name, bool isDirectory, {bool isSearchable = true}) {
    final int? existingId = findNode(parentId, name);
    if (existingId != null) return existingId;
    return insertNode(parentId, name, isDirectory, isSearchable: isSearchable);
  }

  void updateNodeSearchable(int id, bool isSearchable) {
    _db?.execute('UPDATE nodes SET is_searchable = ? WHERE id = ?', <Object?>[isSearchable ? 1 : 0, id]);
  }

  int? cachePath(
    String rootPath,
    String fullPath,
    bool isDirectory, {
    bool rootIsSearchable = true,
    bool directoryIsSearchable = true,
    bool leafIsSearchable = true,
  }) {
    if (!fullPath.startsWith(rootPath)) return null;

    int? currentId = findNode(null, rootPath);
    currentId ??= insertNode(null, rootPath, true, isSearchable: rootIsSearchable);

    if (fullPath == rootPath) return currentId;

    final String relative = fullPath.substring(rootPath.length).replaceFirst(RegExp(r'^[/\\]'), '');
    if (relative.isEmpty) return currentId;

    final List<String> segments = p.split(relative);
    for (int i = 0; i < segments.length; i++) {
      final String segment = segments[i];
      final bool isLast = i == segments.length - 1;
      currentId = upsertNode(
        currentId,
        segment,
        !isLast || isDirectory,
        isSearchable: isLast ? leafIsSearchable : directoryIsSearchable,
      );
    }

    return currentId;
  }

  int? findNode(int? parentId, String name) {
    final Database? db = _db;
    if (db == null) return null;
    final ResultSet results =
        db.select('SELECT id FROM nodes WHERE parent_id IS ? AND name = ?', <Object?>[parentId, name]);
    if (results.isEmpty) return null;
    return results.first['id'] as int;
  }

  List<SearchResultNode> search(String query, {int limit = 20, Set<SearchResultEntryType>? entryTypes}) {
    final Database? db = _db;
    if (db == null || query.trim().isEmpty) return <SearchResultNode>[];

    final String trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) {
      return _searchUsingLike(trimmedQuery, limit: limit, entryTypes: entryTypes);
    }

    final String ftsQuery = '"${trimmedQuery.replaceAll('"', '""')}"';
    try {
      final List<Object?> args = <Object?>[ftsQuery];
      final String typeFilter = _entryTypeFilterSql(entryTypes, args, tableAlias: 'n');
      args.add(limit);
      final ResultSet rows = db.select('''
        SELECT
          n.id,
          n.name,
          n.is_directory,
          n.entry_type,
          n.launch_target,
          n.parsing_name,
          n.app_user_model_id,
          n.subtitle,
          n.stable_identity,
          n.times_opened
        FROM fts_nodes f
        JOIN nodes n ON f.rowid = n.id
        WHERE fts_nodes MATCH ? AND n.is_searchable = 1$typeFilter
        ORDER BY n.times_opened DESC
        LIMIT ?
      ''', args);

      if (rows.isNotEmpty) {
        return _materializeSearchResults(rows);
      }

      return _searchFuzzyFallback(db, trimmedQuery, limit: limit, entryTypes: entryTypes);
    } catch (_) {
      return <SearchResultNode>[];
    }
  }

  List<SearchResultNode> _searchFuzzyFallback(
    Database db,
    String query, {
    int limit = 20,
    Set<SearchResultEntryType>? entryTypes,
  }) {
    final List<String> trigrams = <String>[];
    for (int i = 0; i <= query.length - 3; i++) {
      trigrams.add(query.substring(i, i + 3));
    }
    if (trigrams.isEmpty) return <SearchResultNode>[];

    const int candidateCap = 200;
    final Map<int, _FuzzyCandidate> candidatesById = <int, _FuzzyCandidate>{};

    for (final String trigram in trigrams) {
      if (candidatesById.length >= candidateCap) break;
      try {
        final String tq = '"${trigram.replaceAll('"', '""')}"';
        final List<Object?> args = <Object?>[tq];
        final String typeFilter = _entryTypeFilterSql(entryTypes, args, tableAlias: 'n');
        args.add(candidateCap);
        final ResultSet rows = db.select(
          'SELECT f.rowid as id, n.name, n.is_directory, n.times_opened '
          'FROM fts_nodes f JOIN nodes n ON f.rowid = n.id '
          'WHERE fts_nodes MATCH ? AND n.is_searchable = 1$typeFilter LIMIT ?',
          args,
        );
        for (final Row row in rows) {
          final int id = row['id'] as int;
          if (!candidatesById.containsKey(id)) {
            candidatesById[id] = _FuzzyCandidate(
              id: id,
              name: ((row['name'] as String?) ?? '').toLowerCase(),
              isDirectory: (row['is_directory'] as int? ?? 0) == 1,
              timesOpened: row['times_opened'] as int? ?? 0,
            );
          }
        }
      } catch (_) {}
    }

    if (candidatesById.isEmpty) return <SearchResultNode>[];

    final String lowerQuery = query.toLowerCase();
    final List<_FuzzyCandidate> scored = candidatesById.values
        .map((_FuzzyCandidate c) {
          c.score = _fuzzyScore(c.name, lowerQuery, c.timesOpened);
          return c;
        })
        .where((_FuzzyCandidate c) => c.score > 0)
        .toList();

    if (scored.isEmpty) return <SearchResultNode>[];

    scored.sort((_FuzzyCandidate a, _FuzzyCandidate b) => b.score.compareTo(a.score));
    final List<int> ids = scored.take(limit).map((_FuzzyCandidate c) => c.id).toList(growable: false);
    return _materializeNodesById(ids);
  }

  static double _fuzzyScore(String name, String query, int timesOpened) {
    final int dotIndex = name.lastIndexOf('.');
    final String stem = dotIndex > 0 ? name.substring(0, dotIndex) : name;

    if (name.contains(query)) return 1000.0 + timesOpened;

    if (_isSubsequence(query, name)) {
      final double density = query.length / name.length;
      return 500.0 + density * 100 + timesOpened;
    }

    if (stem != name && _isSubsequence(query, stem)) {
      final double density = query.length / stem.length;
      return 450.0 + density * 100 + timesOpened;
    }

    final double trigramOverlap = _trigramOverlap(query, name);
    if (trigramOverlap >= 0.5) {
      return 200.0 + trigramOverlap * 100 + timesOpened;
    }

    if (name.length <= query.length + 4) {
      final int dist = _editDistance(query, stem.length <= query.length + 2 ? stem : name);
      final int maxAllowed = (query.length / 3).ceil().clamp(1, 3);
      if (dist <= maxAllowed) {
        return 100.0 + (maxAllowed - dist) * 30.0 + timesOpened;
      }
    }

    return 0.0;
  }

  static bool _isSubsequence(String pattern, String text) {
    int pi = 0;
    for (int ti = 0; ti < text.length && pi < pattern.length; ti++) {
      if (text[ti] == pattern[pi]) pi++;
    }
    return pi == pattern.length;
  }

  static double _trigramOverlap(String query, String text) {
    if (query.length < 3) return 0.0;
    int hits = 0;
    final int total = query.length - 2;
    for (int i = 0; i < total; i++) {
      if (text.contains(query.substring(i, i + 3))) hits++;
    }
    return hits / total;
  }

  static int _editDistance(String a, String b, {int maxDist = 4}) {
    if ((a.length - b.length).abs() > maxDist) return maxDist + 1;
    final List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
    final List<int> current = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      current[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = <int>[
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + cost,
        ].reduce((int x, int y) => x < y ? x : y);
      }
      previous.setAll(0, current);
    }
    return previous[b.length];
  }

  List<SearchResultNode> _searchUsingLike(
    String query, {
    int limit = 20,
    Set<SearchResultEntryType>? entryTypes,
  }) {
    final Database? db = _db;
    if (db == null) return <SearchResultNode>[];

    try {
      final List<Object?> args = <Object?>['%$query%'];
      final String typeFilter = _entryTypeFilterSql(entryTypes, args);
      args.add(limit);
      final ResultSet rows = db.select('''
        SELECT
          id,
          name,
          is_directory,
          entry_type,
          launch_target,
          parsing_name,
          app_user_model_id,
          subtitle,
          stable_identity,
          times_opened
        FROM nodes
        WHERE name LIKE ? AND is_searchable = 1$typeFilter
        ORDER BY times_opened DESC
        LIMIT ?
      ''', args);
      return _materializeSearchResults(rows);
    } catch (_) {
      return <SearchResultNode>[];
    }
  }

  List<SearchResultNode> getTopOpened({int limit = 20, Set<SearchResultEntryType>? entryTypes}) {
    final Database? db = _db;
    if (db == null) return <SearchResultNode>[];
    try {
      final List<Object?> args = <Object?>[];
      final String typeFilter = _entryTypeFilterSql(entryTypes, args);
      args.add(limit);
      final ResultSet rows = db.select('''
        SELECT
          id,
          name,
          is_directory,
          entry_type,
          launch_target,
          parsing_name,
          app_user_model_id,
          subtitle,
          stable_identity,
          times_opened
        FROM nodes
        WHERE times_opened > 0 AND is_searchable = 1$typeFilter
        ORDER BY times_opened DESC
        LIMIT ?
      ''', args);
      return _materializeSearchResults(rows);
    } catch (_) {
      return <SearchResultNode>[];
    }
  }

  List<SearchResultNode> getChildNodes(int parentId) {
    final Database? db = _db;
    if (db == null) return <SearchResultNode>[];
    final ResultSet rows = db.select('''
      SELECT
        id,
        name,
        is_directory,
        entry_type,
        launch_target,
        parsing_name,
        app_user_model_id,
        subtitle,
        stable_identity,
        times_opened
      FROM nodes
      WHERE parent_id = ?
      ORDER BY name COLLATE NOCASE
    ''', <Object?>[parentId]);
    return _materializeSearchResults(rows);
  }

  SearchResultNode? getNode(int nodeId) {
    final Database? db = _db;
    if (db == null) return null;
    final ResultSet rows = db.select('''
      SELECT
        id,
        name,
        is_directory,
        entry_type,
        launch_target,
        parsing_name,
        app_user_model_id,
        subtitle,
        stable_identity,
        times_opened
      FROM nodes
      WHERE id = ?
      LIMIT 1
    ''', <Object?>[nodeId]);
    if (rows.isEmpty) return null;
    return _materializeSearchResult(rows.first);
  }

  List<SearchResultNode> _materializeNodesById(Iterable<int> ids) {
    final List<SearchResultNode> nodes = <SearchResultNode>[];
    for (final int id in ids) {
      final SearchResultNode? node = getNode(id);
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  List<SearchResultNode> _materializeSearchResults(ResultSet rows) {
    return rows.map(_materializeSearchResult).toList(growable: false);
  }

  SearchResultNode _materializeSearchResult(Row row) {
    final SearchResultEntryType entryType = _entryTypeFromDbValue((row['entry_type'] as String?) ?? 'file');
    final int id = row['id'] as int;
    final String name = (row['name'] as String?) ?? '';
    final bool isDirectory = (row['is_directory'] as int? ?? 0) == 1;

    if (entryType == SearchResultEntryType.app) {
      return SearchResultNode(
        id: id,
        path: (row['launch_target'] as String?) ?? '',
        name: name,
        isDirectory: false,
        entryType: entryType,
        launchTarget: row['launch_target'] as String?,
        parsingName: row['parsing_name'] as String?,
        appUserModelId: row['app_user_model_id'] as String?,
        subtitle: row['subtitle'] as String?,
        stableIdentity: row['stable_identity'] as String?,
      );
    }

    final String resolvedPath = getAbsolutePath(id) ?? name;
    return SearchResultNode(
      id: id,
      path: resolvedPath,
      name: name,
      isDirectory: isDirectory,
      entryType: entryType,
    );
  }

  String _entryTypeFilterSql(Set<SearchResultEntryType>? entryTypes, List<Object?> args, {String tableAlias = ''}) {
    if (entryTypes == null || entryTypes.isEmpty) return '';
    final String prefix = tableAlias.isEmpty ? '' : '$tableAlias.';
    final String placeholders = List<String>.filled(entryTypes.length, '?').join(', ');
    args.addAll(entryTypes.map(_entryTypeToDbValue));
    return ' AND ${prefix}entry_type IN ($placeholders)';
  }

  String _entryTypeToDbValue(SearchResultEntryType entryType) {
    switch (entryType) {
      case SearchResultEntryType.app:
        return 'app';
      case SearchResultEntryType.file:
        return 'file';
    }
  }

  SearchResultEntryType _entryTypeFromDbValue(String value) {
    return value == 'app' ? SearchResultEntryType.app : SearchResultEntryType.file;
  }

  void close() {
    _db?.close();
    _db = null;
  }
}

class _FuzzyCandidate {
  final int id;
  final String name;
  final bool isDirectory;
  final int timesOpened;
  double score = 0.0;

  _FuzzyCandidate({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.timesOpened,
  });
}
