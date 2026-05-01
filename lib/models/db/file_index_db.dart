import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../win32/win_utils.dart';

class FileIndexDb {
  FileIndexDb._();
  static final FileIndexDb instance = FileIndexDb._();

  Database? _db;
  String? _manualPath;
  String dbName = kReleaseMode ? 'file_index.db' : 'file_index_debug.db';
  String get dbPath {
    if (_manualPath != null) return _manualPath!;
    final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
    return p.join(appDir.path, dbName);
  }

  /// Sets a manual database path. Useful for background isolates where
  /// path_provider might not be available.
  void setDatabasePath(String path) {
    _manualPath = path;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    String dbPath;
    if (_manualPath != null) {
      dbPath = _manualPath!;
    } else {
      final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
      dbPath = p.join(appDir.path, dbName);
    }

    try {
      return _openAndSetupDb(dbPath);
    } catch (e) {
      if (e.toString().contains('malformed')) {
        debugPrint('FileIndexDb: Database is malformed, attempting to recreate...');
        await repair();
        return _openAndSetupDb(dbPath);
      }
      rethrow;
    }
  }

  /// Closes and deletes the database files.
  Future<void> repair() async {
    _db?.close();
    _db = null;

    final Directory appDir = Directory(WinUtils.getTabameAppDataFolder());
    final String dbPath = p.join(appDir.path, dbName);

    final File dbFile = File(dbPath);
    if (await dbFile.exists()) {
      try {
        await dbFile.delete();
        final File walFile = File('$dbPath-wal');
        final File shmFile = File('$dbPath-shm');
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

    // Enable WAL mode for better concurrency
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');

    // Adjacency list table for memory efficiency
    db.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        name TEXT NOT NULL,
        is_directory INTEGER NOT NULL,
        times_opened INTEGER NOT NULL DEFAULT 0,
        is_searchable INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(parent_id) REFERENCES nodes(id) ON DELETE CASCADE
      );
    ''');

    // Migration for existing DBs
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN times_opened INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      db.execute('ALTER TABLE nodes ADD COLUMN is_searchable INTEGER NOT NULL DEFAULT 1;');
    } catch (_) {}

    // Index for fast parent/child lookups
    db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_parent_id ON nodes(parent_id);');

    // FTS5 Trigram index for fast fuzzy searching
    try {
      db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_nodes USING fts5(
          name,
          content='nodes',
          content_rowid='id',
          tokenize="trigram"
        );
      ''');

      // Trigger to keep FTS in sync
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

  /// Returns the total number of nodes under a given root path.
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

  /// Reconstructs the absolute path from a node ID using a Recursive CTE.
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

  /// Inserts a node into the database. Returns the new ID.
  int insertNode(int? parentId, String name, bool isDirectory, {bool isSearchable = true}) {
    final Database? db = _db;
    if (db == null) throw StateError('FileIndexDb: Database not initialized');
    final PreparedStatement stmt =
        db.prepare('INSERT INTO nodes (parent_id, name, is_directory, is_searchable) VALUES (?, ?, ?, ?)');
    stmt.execute(<Object?>[parentId, name, isDirectory ? 1 : 0, isSearchable ? 1 : 0]);
    final int id = db.lastInsertRowId;
    stmt.close();
    return id;
  }

  /// Increments the times_opened count for a node.
  void incrementTimesOpened(int id) {
    _db?.execute('UPDATE nodes SET times_opened = times_opened + 1 WHERE id = ?', <Object?>[id]);
  }

  /// Deletes a node and all its children (via cascade).
  void deleteNode(int id) {
    _db?.execute('DELETE FROM nodes WHERE id = ?', <Object?>[id]);
  }

  /// Deletes all children of a node.
  void deleteChildren(int parentId) {
    _db?.execute('DELETE FROM nodes WHERE parent_id = ?', <Object?>[parentId]);
  }

  int upsertNode(int? parentId, String name, bool isDirectory, {bool isSearchable = true}) {
    final int? existingId = findNode(parentId, name);
    if (existingId != null) return existingId;
    return insertNode(parentId, name, isDirectory, isSearchable: isSearchable);
  }

  void updateNodeSearchable(int id, bool isSearchable) {
    _db?.execute('UPDATE nodes SET is_searchable = ? WHERE id = ?', <Object?>[isSearchable ? 1 : 0, id]);
  }

  /// Ensures a full path is indexed, creating parent nodes as needed.
  /// Returns the ID of the leaf node.
  int? cachePath(
    String rootPath,
    String fullPath,
    bool isDirectory, {
    bool rootIsSearchable = true,
    bool directoryIsSearchable = true,
    bool leafIsSearchable = true,
  }) {
    if (!fullPath.startsWith(rootPath)) return null;

    // Ensure root exists
    int? currentId = findNode(null, rootPath);
    currentId ??= insertNode(null, rootPath, true, isSearchable: rootIsSearchable);

    if (fullPath == rootPath) return currentId;

    final String relative = fullPath.substring(rootPath.length).replaceFirst(RegExp(r'^[/\\]'), '');
    if (relative.isEmpty) return currentId;

    final List<String> segments = p.split(relative);
    for (int i = 0; i < segments.length; i++) {
      final String segment = segments[i];
      final bool isLast = i == segments.length - 1;
      // We assume intermediate segments are directories
      currentId = upsertNode(
        currentId,
        segment,
        !isLast || isDirectory,
        isSearchable: isLast ? leafIsSearchable : directoryIsSearchable,
      );
    }

    return currentId;
  }

  /// Finds a node by name and parent.
  int? findNode(int? parentId, String name) {
    final Database? db = _db;
    if (db == null) return null;
    final ResultSet results =
        db.select('SELECT id FROM nodes WHERE parent_id IS ? AND name = ?', <Object?>[parentId, name]);
    if (results.isEmpty) return null;
    return results.first['id'] as int;
  }

  /// Searches for files using fuzzy matching and returns reconstructed paths.
  List<SearchResultNode> search(String query, {int limit = 20}) {
    final Database? db = _db;
    if (db == null || query.trim().isEmpty) return <SearchResultNode>[];

    // FTS5 Trigram handles partial matches well, but requires at least 3 chars
    // to avoid errors in MATCH. For shorter queries, we fallback to LIKE.
    final String trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) {
      return _searchUsingLike(trimmedQuery, limit: limit);
    }

    final String ftsQuery = '"${trimmedQuery.replaceAll('"', '""')}"';

    try {
      final ResultSet results = db.select('''
        WITH RECURSIVE matched_nodes AS (
          SELECT f.rowid as id 
          FROM fts_nodes f
          JOIN nodes n ON f.rowid = n.id
          WHERE fts_nodes MATCH ? 
          ORDER BY n.times_opened DESC
          LIMIT ?
        ),
        path_cte(root_id, id, parent_id, name, is_directory, full_path) AS (
          SELECT n.id, n.id, n.parent_id, n.name, n.is_directory, n.name 
          FROM nodes n
          JOIN matched_nodes m ON n.id = m.id
          UNION ALL
          SELECT c.root_id, p.id, p.parent_id, p.name, p.is_directory, 
                 p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path 
          FROM nodes p
          JOIN path_cte c ON c.parent_id = p.id
        )
        SELECT root_id, full_path, is_directory 
        FROM path_cte 
        WHERE parent_id IS NULL;
      ''', <Object?>[ftsQuery, limit]);

      if (results.isNotEmpty) {
        return results
            .map((Row row) => SearchResultNode(
                  id: row['root_id'] as int,
                  path: row['full_path'] as String,
                  isDirectory: (row['is_directory'] as int) == 1,
                ))
            .toList();
      }

      // No exact substring match — run fuzzy trigram fallback.
      return _searchFuzzyFallback(db, trimmedQuery, limit: limit);
    } catch (e) {
      return <SearchResultNode>[];
    }
  }

  /// Fuzzy fallback: decompose the query into individual trigrams, query each
  /// separately via FTS5, deduplicate candidates, then rank them in Dart using
  /// a subsequence check + edit distance so that typos like "chrme" → "chrome"
  /// still surface relevant results.
  List<SearchResultNode> _searchFuzzyFallback(Database db, String query, {int limit = 20}) {
    // Build the set of 3-char windows from the query.
    final List<String> trigrams = <String>[];
    for (int i = 0; i <= query.length - 3; i++) {
      trigrams.add(query.substring(i, i + 3));
    }
    if (trigrams.isEmpty) return <SearchResultNode>[];

    // Candidate pool: fetch nodes matching ANY trigram (limit generously, we'll
    // re-rank and trim in Dart). Use a large internal cap to avoid too many
    // round trips while still bounding memory.
    const int candidateCap = 200;
    final Map<int, _FuzzyCandidate> candidatesById = <int, _FuzzyCandidate>{};

    for (final String trigram in trigrams) {
      if (candidatesById.length >= candidateCap) break;
      try {
        final String tq = '"${trigram.replaceAll('"', '""')}"';
        final ResultSet rows = db.select(
          'SELECT f.rowid as id, n.name, n.is_directory, n.times_opened '
          'FROM fts_nodes f JOIN nodes n ON f.rowid = n.id '
          'WHERE fts_nodes MATCH ? LIMIT ?',
          <Object?>[tq, candidateCap],
        );
        for (final Row row in rows) {
          final int id = row['id'] as int;
          if (!candidatesById.containsKey(id)) {
            candidatesById[id] = _FuzzyCandidate(
              id: id,
              name: (row['name'] as String).toLowerCase(),
              isDirectory: (row['is_directory'] as int) == 1,
              timesOpened: row['times_opened'] as int? ?? 0,
            );
          }
        }
      } catch (_) {}
    }

    if (candidatesById.isEmpty) return <SearchResultNode>[];

    // Score each candidate in Dart.
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
    final List<_FuzzyCandidate> top = scored.take(limit).toList();

    // Resolve full paths via the recursive CTE.
    final List<SearchResultNode> nodes = <SearchResultNode>[];
    for (final _FuzzyCandidate c in top) {
      try {
        final ResultSet pathRows = db.select('''
          WITH RECURSIVE path_cte(root_id, id, parent_id, name, is_directory, full_path) AS (
            SELECT n.id, n.id, n.parent_id, n.name, n.is_directory, n.name 
            FROM nodes n WHERE n.id = ?
            UNION ALL
            SELECT c.root_id, p.id, p.parent_id, p.name, p.is_directory, 
                   p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path 
            FROM nodes p JOIN path_cte c ON c.parent_id = p.id
          )
          SELECT root_id, full_path, is_directory FROM path_cte WHERE parent_id IS NULL;
        ''', <Object?>[c.id]);
        if (pathRows.isNotEmpty) {
          nodes.add(SearchResultNode(
            id: pathRows.first['root_id'] as int,
            path: pathRows.first['full_path'] as String,
            isDirectory: (pathRows.first['is_directory'] as int) == 1,
          ));
        }
      } catch (_) {}
    }
    return nodes;
  }

  /// Scores how well [name] matches [query].
  /// Returns 0 if the match is too poor to surface.
  /// Higher = better match.
  static double _fuzzyScore(String name, String query, int timesOpened) {
    // Strip extension for scoring (keep ext-less name for comparison).
    final int dotIndex = name.lastIndexOf('.');
    final String stem = dotIndex > 0 ? name.substring(0, dotIndex) : name;

    // 1. Exact substring — highest tier.
    if (name.contains(query)) return 1000.0 + timesOpened;

    // 2. Subsequence match: every character of query appears in order in name.
    //    This handles skipped letters ("chrme" → "chrome").
    if (_isSubsequence(query, name)) {
      // Reward shorter names (closer match) and frequency.
      final double density = query.length / name.length;
      return 500.0 + density * 100 + timesOpened;
    }

    // 3. Loose subsequence against stem only (e.g. ignore extension).
    if (stem != name && _isSubsequence(query, stem)) {
      final double density = query.length / stem.length;
      return 450.0 + density * 100 + timesOpened;
    }

    // 4. Trigram overlap ratio: how many 3-char windows of query appear in name.
    final double trigramOverlap = _trigramOverlap(query, name);
    if (trigramOverlap >= 0.5) {
      return 200.0 + trigramOverlap * 100 + timesOpened;
    }

    // 5. Edit distance — only for short names where it makes sense.
    if (name.length <= query.length + 4) {
      final int dist = _editDistance(query, stem.length <= query.length + 2 ? stem : name);
      final int maxAllowed = (query.length / 3).ceil().clamp(1, 3);
      if (dist <= maxAllowed) {
        return 100.0 + (maxAllowed - dist) * 30.0 + timesOpened;
      }
    }

    return 0.0;
  }

  /// Returns true if every character in [pattern] appears in [text] in order.
  static bool _isSubsequence(String pattern, String text) {
    int pi = 0;
    for (int ti = 0; ti < text.length && pi < pattern.length; ti++) {
      if (text[ti] == pattern[pi]) pi++;
    }
    return pi == pattern.length;
  }

  /// Returns the fraction of 3-char windows in [query] that appear in [text].
  static double _trigramOverlap(String query, String text) {
    if (query.length < 3) return 0.0;
    int hits = 0;
    final int total = query.length - 2;
    for (int i = 0; i < total; i++) {
      if (text.contains(query.substring(i, i + 3))) hits++;
    }
    return hits / total;
  }

  /// Classic Levenshtein edit distance (capped at [maxDist] for performance).
  static int _editDistance(String a, String b, {int maxDist = 4}) {
    if ((a.length - b.length).abs() > maxDist) return maxDist + 1;
    final List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
    final List<int> curr = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        curr[j] = a[i - 1] == b[j - 1] ? prev[j - 1] : 1 + prev[j - 1].clamp(0, prev[j]).clamp(0, curr[j - 1]);
      }
      prev.setAll(0, curr);
    }
    return prev[b.length];
  }

  List<SearchResultNode> _searchUsingLike(String query, {int limit = 20}) {
    final Database? db = _db;
    if (db == null) return <SearchResultNode>[];

    try {
      final ResultSet results = db.select('''
        WITH matched_nodes AS (
          SELECT id 
          FROM nodes 
          WHERE name LIKE ? AND is_searchable = 1
          ORDER BY times_opened DESC
          LIMIT ?
        ),
        path_cte(root_id, id, parent_id, name, is_directory, full_path) AS (
          SELECT n.id, n.id, n.parent_id, n.name, n.is_directory, n.name 
          FROM nodes n
          JOIN matched_nodes m ON n.id = m.id
          UNION ALL
          SELECT c.root_id, p.id, p.parent_id, p.name, p.is_directory, 
                 p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path 
          FROM nodes p
          JOIN path_cte c ON c.parent_id = p.id
        )
        SELECT root_id, full_path, is_directory 
        FROM path_cte 
        WHERE parent_id IS NULL;
      ''', <Object?>['%$query%', limit]);

      return results
          .map((Row row) => SearchResultNode(
                id: row['root_id'] as int,
                path: row['full_path'] as String,
                isDirectory: (row['is_directory'] as int) == 1,
              ))
          .toList();
    } catch (e) {
      print(e);
      return <SearchResultNode>[];
    }
  }

  /// Returns the top N most opened nodes.
  List<SearchResultNode> getTopOpened({int limit = 20}) {
    final Database? db = _db;
    if (db == null) return <SearchResultNode>[];
    try {
      final ResultSet results = db.select('''
       WITH RECURSIVE path_cte(root_id, id, parent_id, name, is_directory, full_path) AS (
  SELECT n.id, n.id, n.parent_id, n.name, n.is_directory, n.name 
  FROM nodes n
  WHERE n.times_opened > 0 AND n.is_searchable = 1
  UNION ALL
  SELECT c.root_id, p.id, p.parent_id, p.name, p.is_directory, 
         p.name || (CASE WHEN p.name LIKE '_:\\' OR p.name LIKE '\\\\%' THEN '' ELSE '\\' END) || c.full_path 
  FROM nodes p
  JOIN path_cte c ON c.parent_id = p.id
)
SELECT 
    root_id, 
    full_path, 
    path_cte.is_directory, -- Prefix added here
    n.times_opened
FROM path_cte
JOIN nodes n ON path_cte.root_id = n.id -- Good practice to prefix join keys too
WHERE path_cte.parent_id IS NULL
ORDER BY n.times_opened DESC
LIMIT ?;
      ''', <Object?>[limit]);

      return results
          .map((Row row) => SearchResultNode(
                id: row['root_id'] as int,
                path: row['full_path'] as String,
                isDirectory: (row['is_directory'] as int) == 1,
              ))
          .toList();
    } catch (e) {
      print(e);
      return <SearchResultNode>[];
    }
  }

  void close() {
    _db?.close();
    _db = null;
  }
}

class SearchResultNode {
  final int id;
  final String path;
  final bool isDirectory;
  SearchResultNode({required this.id, required this.path, required this.isDirectory});
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
