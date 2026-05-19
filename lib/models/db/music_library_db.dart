import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../classes/music_server.dart';
import '../win32/win_utils.dart';

class MusicRoot {
  const MusicRoot({
    required this.id,
    required this.path,
  });

  final int id;
  final String path;

  String get title {
    final String name = p.basename(path);
    final String result = name.trim().isEmpty ? path : name;
    return MusicLibraryDb.sanitize(result);
  }
}

class MusicArtworkRecord {
  const MusicArtworkRecord({
    required this.artworkHash,
    required this.smallPath,
    required this.largePath,
    required this.sourcePath,
    required this.sourceModifiedMillis,
  });

  final String artworkHash;
  final String smallPath;
  final String largePath;
  final String sourcePath;
  final int sourceModifiedMillis;
}

class LocalMusicMetadata {
  const LocalMusicMetadata({
    required this.path,
    required this.rootPath,
    required this.parentPath,
    required this.title,
    required this.fileSize,
    required this.modifiedMillis,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.trackIndex,
    this.trackCount,
    this.discIndex,
    this.discCount,
    this.durationSeconds,
    this.artworkHash,
    this.artworkSmallPath,
    this.artworkLargePath,
    this.artworkSourcePath,
    this.artworkSourceModifiedMillis,
  });

  final String path;
  final String rootPath;
  final String parentPath;
  final String title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? trackIndex;
  final int? trackCount;
  final int? discIndex;
  final int? discCount;
  final int? durationSeconds;
  final String? artworkHash;
  final String? artworkSmallPath;
  final String? artworkLargePath;
  final String? artworkSourcePath;
  final int? artworkSourceModifiedMillis;
  final int fileSize;
  final int modifiedMillis;
}

class MusicLibraryDb {
  MusicLibraryDb._();
  static final MusicLibraryDb instance = MusicLibraryDb._();

  static const String songIdPrefix = 'local:song:';
  static const String artistIdPrefix = 'local:artist:';
  static const String albumIdPrefix = 'local:album:';
  static const String folderIdPrefix = 'local:folder:';

  Database? _db;
  Completer<Database>? _dbCompleter;
  String? _manualPath;
  String dbName = 'music_library.db';

  String get dbPath {
    if (_manualPath != null) return _manualPath!;
    return p.join(WinUtils.getTabameAppDataFolder(), dbName);
  }

  void setDatabasePath(String path) {
    close();
    _manualPath = path;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_dbCompleter != null) return _dbCompleter!.future;
    _dbCompleter = Completer<Database>();
    try {
      _db = _openAndSetupDb(dbPath);
      _dbCompleter!.complete(_db!);
    } catch (e, stack) {
      final Completer<Database> failed = _dbCompleter!;
      _dbCompleter = null;
      failed.completeError(e, stack);
    }
    return _dbCompleter!.future;
  }

  Database _openAndSetupDb(String path) {
    final File dbFile = File(path);
    if (!dbFile.parent.existsSync()) dbFile.parent.createSync(recursive: true);

    final Database db = sqlite3.open(path);
    db.execute('PRAGMA cache_size = -2000;'); // Limit to 2 MB (default is 2000 pages)
    db.execute('PRAGMA temp_store = MEMORY;');
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS music_roots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        normalized_path TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL,
        normalized_path TEXT NOT NULL UNIQUE,
        parent_path TEXT NOT NULL,
        normalized_parent_path TEXT NOT NULL,
        root_path TEXT NOT NULL,
        normalized_root_path TEXT NOT NULL,
        title TEXT NOT NULL,
        artist TEXT,
        album TEXT,
        genre TEXT,
        year INTEGER,
        track_index INTEGER,
        track_count INTEGER,
        disc_index INTEGER,
        disc_count INTEGER,
        duration_seconds INTEGER,
        play_count INTEGER NOT NULL DEFAULT 0,
        stars_count INTEGER NOT NULL DEFAULT 0,
        last_played_at TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_millis INTEGER NOT NULL DEFAULT 0,
        artwork_hash TEXT,
        artwork_small_path TEXT,
        artwork_large_path TEXT,
        artwork_source_path TEXT,
        artwork_source_modified_millis INTEGER,
        indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        index_token TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS music_artwork (
        artwork_hash TEXT PRIMARY KEY,
        small_path TEXT NOT NULL,
        large_path TEXT NOT NULL,
        source_path TEXT NOT NULL,
        source_modified_millis INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id TEXT NOT NULL,
        song_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
      );
    ''');
    _addColumnIfMissing(db, 'songs', 'artwork_hash', 'TEXT');
    _addColumnIfMissing(db, 'songs', 'artwork_small_path', 'TEXT');
    _addColumnIfMissing(db, 'songs', 'artwork_large_path', 'TEXT');
    _addColumnIfMissing(db, 'songs', 'artwork_source_path', 'TEXT');
    _addColumnIfMissing(db, 'songs', 'artwork_source_modified_millis', 'INTEGER');
    db.execute('CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs(artist);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_songs_album ON songs(album);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_songs_parent ON songs(normalized_parent_path);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_songs_root ON songs(normalized_root_path);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_songs_artwork_hash ON songs(artwork_hash);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_playlist_songs_position ON playlist_songs(playlist_id, position);');
    return db;
  }

  void _addColumnIfMissing(Database db, String table, String column, String definition) {
    final ResultSet rows = db.select('PRAGMA table_info($table)');
    final bool exists = rows.any((Row row) => row['name'] == column);
    if (!exists) db.execute('ALTER TABLE $table ADD COLUMN $column $definition;');
  }

  Future<List<MusicRoot>> getRoots() async {
    final Database db = await database;
    final ResultSet rows = db.select('SELECT id, path FROM music_roots ORDER BY path COLLATE NOCASE');
    return rows.map((Row row) => MusicRoot(id: row['id'] as int, path: row['path'] as String)).toList();
  }

  Future<void> addRoot(String path) async {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final Database db = await database;
    db.execute(
      'INSERT OR IGNORE INTO music_roots(path, normalized_path) VALUES(?, ?)',
      <Object?>[p.normalize(trimmed), normalizePath(trimmed)],
    );
  }

  Future<void> removeRoot(String path) async {
    final Database db = await database;
    final String normalized = normalizePath(path);
    db.execute('DELETE FROM music_roots WHERE normalized_path = ?', <Object?>[normalized]);
    db.execute('DELETE FROM songs WHERE normalized_root_path = ?', <Object?>[normalized]);
  }

  Future<int> countSongs() async {
    final Database db = await database;
    final ResultSet rows = db.select('SELECT COUNT(*) AS total FROM songs');
    return rows.first['total'] as int;
  }

  Future<MusicArtworkRecord?> getArtworkRecord(String artworkHash) async {
    final Database db = await database;
    final ResultSet rows = db.select('SELECT * FROM music_artwork WHERE artwork_hash = ?', <Object?>[artworkHash]);
    if (rows.isEmpty) return null;
    final Row row = rows.first;
    return MusicArtworkRecord(
      artworkHash: row['artwork_hash'] as String,
      smallPath: row['small_path'] as String,
      largePath: row['large_path'] as String,
      sourcePath: row['source_path'] as String,
      sourceModifiedMillis: row['source_modified_millis'] as int,
    );
  }

  Future<void> upsertArtworkRecord(MusicArtworkRecord record) async {
    final Database db = await database;
    db.execute('''
      INSERT INTO music_artwork (
        artwork_hash,
        small_path,
        large_path,
        source_path,
        source_modified_millis,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(artwork_hash) DO UPDATE SET
        small_path = excluded.small_path,
        large_path = excluded.large_path,
        source_path = excluded.source_path,
        source_modified_millis = excluded.source_modified_millis,
        updated_at = CURRENT_TIMESTAMP
    ''', <Object?>[
      record.artworkHash,
      record.smallPath,
      record.largePath,
      record.sourcePath,
      record.sourceModifiedMillis,
    ]);
  }

  Future<int> upsertSong(LocalMusicMetadata metadata, String indexToken) async {
    final Database db = await database;
    final String normalizedPath = normalizePath(metadata.path);
    db.execute('''
      INSERT INTO songs (
        path,
        normalized_path,
        parent_path,
        normalized_parent_path,
        root_path,
        normalized_root_path,
        title,
        artist,
        album,
        genre,
        year,
        track_index,
        track_count,
        disc_index,
        disc_count,
        duration_seconds,
        artwork_hash,
        artwork_small_path,
        artwork_large_path,
        artwork_source_path,
        artwork_source_modified_millis,
        file_size,
        modified_millis,
        indexed_at,
        index_token
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
      ON CONFLICT(normalized_path) DO UPDATE SET
        path = excluded.path,
        parent_path = excluded.parent_path,
        normalized_parent_path = excluded.normalized_parent_path,
        root_path = excluded.root_path,
        normalized_root_path = excluded.normalized_root_path,
        title = excluded.title,
        artist = excluded.artist,
        album = excluded.album,
        genre = excluded.genre,
        year = excluded.year,
        track_index = excluded.track_index,
        track_count = excluded.track_count,
        disc_index = excluded.disc_index,
        disc_count = excluded.disc_count,
        duration_seconds = excluded.duration_seconds,
        artwork_hash = excluded.artwork_hash,
        artwork_small_path = excluded.artwork_small_path,
        artwork_large_path = excluded.artwork_large_path,
        artwork_source_path = excluded.artwork_source_path,
        artwork_source_modified_millis = excluded.artwork_source_modified_millis,
        file_size = excluded.file_size,
        modified_millis = excluded.modified_millis,
        indexed_at = CURRENT_TIMESTAMP,
        index_token = excluded.index_token
    ''', <Object?>[
      metadata.path,
      normalizedPath,
      metadata.parentPath,
      normalizePath(metadata.parentPath),
      metadata.rootPath,
      normalizePath(metadata.rootPath),
      _fallbackTitle(metadata.title, metadata.path),
      _blankToNull(metadata.artist),
      _blankToNull(metadata.album),
      _blankToNull(metadata.genre),
      metadata.year,
      metadata.trackIndex,
      metadata.trackCount,
      metadata.discIndex,
      metadata.discCount,
      metadata.durationSeconds,
      metadata.artworkHash,
      metadata.artworkSmallPath,
      metadata.artworkLargePath,
      metadata.artworkSourcePath,
      metadata.artworkSourceModifiedMillis,
      metadata.fileSize,
      metadata.modifiedMillis,
      indexToken,
    ]);

    final ResultSet rows = db.select('SELECT id FROM songs WHERE normalized_path = ?', <Object?>[normalizedPath]);
    return rows.first['id'] as int;
  }

  Future<void> deleteSongsNotIndexedInScope({
    required String rootPath,
    required String scopePath,
    required String indexToken,
  }) async {
    final Database db = await database;
    final String normalizedRoot = normalizePath(rootPath);
    final String normalizedScope = normalizePath(scopePath);
    db.execute(
      '''
      DELETE FROM songs
      WHERE normalized_root_path = ?
        AND (normalized_path = ? OR normalized_path LIKE ? ESCAPE '~')
        AND (index_token IS NULL OR index_token != ?)
      ''',
      <Object?>[normalizedRoot, normalizedScope, '${_escapeLike(normalizedScope)}\\%', indexToken],
    );
  }

  Future<List<MusicItem>> getArtists() async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') AS name, COUNT(*) AS total
      FROM songs
      GROUP BY name
      ORDER BY name COLLATE NOCASE
    ''');
    return rows
        .map((Row row) => MusicItem(
              id: '$artistIdPrefix${row['name']}',
              title: row['name'] as String,
              isFolder: true,
              type: MusicItemType.artist,
            ))
        .toList();
  }

  Future<List<MusicItem>> getAlbums(String artistId) async {
    final Database db = await database;
    final String artist = artistId.substring(artistIdPrefix.length);
    final ResultSet rows = db.select('''
      SELECT COALESCE(NULLIF(TRIM(album), ''), 'Unknown Album') AS name,
             COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') AS artist_name,
             COUNT(*) AS total,
             SUM(COALESCE(duration_seconds, 0)) AS duration_seconds,
             MAX(artwork_hash) AS artwork_hash,
             MAX(artwork_small_path) AS artwork_small_path,
             MAX(artwork_large_path) AS artwork_large_path
      FROM songs
      WHERE COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') = ?
      GROUP BY name, artist_name
      ORDER BY name COLLATE NOCASE
    ''', <Object?>[artist]);
    return rows.map((Row row) {
      final String album = row['name'] as String;
      return MusicItem(
        id: '$albumIdPrefix${Uri.encodeComponent(artist)}|${Uri.encodeComponent(album)}',
        title: album,
        artist: row['artist_name'] as String,
        artworkHash: row['artwork_hash'] as String?,
        localArtworkSmallPath: row['artwork_small_path'] as String?,
        localArtworkLargePath: row['artwork_large_path'] as String?,
        isFolder: true,
        type: MusicItemType.album,
        duration: _durationFromSeconds(row['duration_seconds']),
      );
    }).toList();
  }

  Future<List<MusicItem>> getAlbumSongs(String albumId) async {
    final ({String artist, String album}) parsed = parseAlbumId(albumId);
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT *
      FROM songs
      WHERE COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') = ?
        AND COALESCE(NULLIF(TRIM(album), ''), 'Unknown Album') = ?
      ORDER BY COALESCE(disc_index, 0), COALESCE(track_index, 999999), title COLLATE NOCASE
    ''', <Object?>[parsed.artist, parsed.album]);
    return rows.map(_songFromRow).toList();
  }

  Future<MusicItem?> getSongByItemId(String itemId) async {
    final int? id = parseSongId(itemId);
    if (id == null) return null;
    final Database db = await database;
    final ResultSet rows = db.select('SELECT * FROM songs WHERE id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return _songFromRow(rows.first);
  }

  Future<List<MusicItem>> getRootFolders() async {
    final Database db = await database;
    final List<MusicRoot> roots = await getRoots();
    return roots.map((MusicRoot root) {
      final ({String? hash, String? largePath, String? smallPath}) poster = _folderPosterForPath(db, root.path);
      return MusicItem(
        id: '$folderIdPrefix${root.path}',
        title: root.title,
        localPath: root.path,
        parentPath: p.dirname(root.path),
        isFolder: true,
        type: MusicItemType.folder,
        artworkHash: poster.hash,
        localArtworkSmallPath: poster.smallPath,
        localArtworkLargePath: poster.largePath,
      );
    }).toList();
  }

  Future<List<MusicItem>> getDirectory(String directoryId) async {
    final String path = parseFolderId(directoryId);
    return getDirectoryByPath(path);
  }

  Future<List<MusicItem>> getDirectoryByPath(String folderPath) async {
    final Database db = await database;
    final String normalizedFolder = normalizePath(folderPath);
    final ResultSet directSongRows = db.select(
      'SELECT * FROM songs WHERE normalized_parent_path = ? ORDER BY COALESCE(track_index, 999999), title COLLATE NOCASE',
      <Object?>[normalizedFolder],
    );
    final ResultSet descendantRows = db.select(
      '''
      SELECT parent_path
      FROM songs
      WHERE normalized_path LIKE ? ESCAPE '~'
        AND normalized_parent_path != ?
      ''',
      <Object?>['${_escapeLike(normalizedFolder)}\\%', normalizedFolder],
    );

    final Map<String, String> childFolders = <String, String>{};
    for (final Row row in descendantRows) {
      final String parentPath = row['parent_path'] as String;
      final String? child = _directChildFolder(folderPath, parentPath);
      if (child != null) childFolders[normalizePath(child)] = child;
    }

    final List<MusicItem> folders = childFolders.values.map((String childPath) {
      final ({String? hash, String? largePath, String? smallPath}) poster = _folderPosterForPath(db, childPath);
      return MusicItem(
        id: '$folderIdPrefix$childPath',
        title: sanitize(p.basename(childPath)),
        localPath: childPath,
        parentPath: folderPath,
        isFolder: true,
        type: MusicItemType.folder,
        artworkHash: poster.hash,
        localArtworkSmallPath: poster.smallPath,
        localArtworkLargePath: poster.largePath,
      );
    }).toList()
      ..sort((MusicItem a, MusicItem b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return <MusicItem>[
      ...folders,
      ...directSongRows.map(_songFromRow),
    ];
  }

  ({String? hash, String? smallPath, String? largePath}) _folderPosterForPath(Database db, String folderPath) {
    final ResultSet rows = db.select(
      '''
      SELECT artwork_hash, artwork_small_path, artwork_large_path
      FROM songs
      WHERE normalized_parent_path = ?
        AND (artwork_small_path IS NOT NULL OR artwork_large_path IS NOT NULL)
      ORDER BY COALESCE(track_index, 999999), title COLLATE NOCASE
      LIMIT 1
      ''',
      <Object?>[normalizePath(folderPath)],
    );

    if (rows.isNotEmpty) {
      final Row row = rows.first;
      final String? smallPath = row['artwork_small_path'] as String?;
      final String? largePath = row['artwork_large_path'] as String?;
      return (
        hash: row['artwork_hash'] as String?,
        smallPath: smallPath ?? largePath,
        largePath: largePath ?? smallPath,
      );
    }

    final String? fallbackPath = _findFolderArtworkPathSync(folderPath);
    return (hash: null, smallPath: fallbackPath, largePath: fallbackPath);
  }

  String? _findFolderArtworkPathSync(String folderPath) {
    final Directory directory = Directory(folderPath);
    if (!directory.existsSync()) return null;

    final Map<String, String> filesByName = <String, String>{};
    try {
      for (final FileSystemEntity entity in directory.listSync(followLinks: false)) {
        if (entity is File) {
          filesByName[p.basename(entity.path).toLowerCase()] = entity.path;
        }
      }
    } catch (_) {
      return null;
    }

    for (final String name in const <String>['album', 'cover', 'Folder', 'folder']) {
      for (final String extension in const <String>['png', 'jpg', 'jpeg']) {
        final String? path = filesByName['$name.$extension'];
        if (path != null) return path;
      }
    }
    return null;
  }

  Future<List<MusicItem>> getDirectorySongsRecursive(String directoryId) async {
    final String path = parseFolderId(directoryId);
    final Database db = await database;
    final String normalizedPath = normalizePath(path);
    final ResultSet rows = db.select(
      '''
      SELECT *
      FROM songs
      WHERE normalized_path LIKE ? ESCAPE '~'
      ORDER BY normalized_parent_path COLLATE NOCASE, COALESCE(track_index, 999999), title COLLATE NOCASE
      ''',
      <Object?>['${_escapeLike(normalizedPath)}\\%'],
    );
    return rows.map(_songFromRow).toList();
  }

  Future<List<MusicItem>> search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return <MusicItem>[];
    final Database db = await database;
    final String like = '%${_escapeLike(trimmed.toLowerCase())}%';

    final ResultSet artistRows = db.select('''
      SELECT COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') AS name
      FROM songs
      GROUP BY name
      HAVING LOWER(name) LIKE ? ESCAPE '~'
      ORDER BY name COLLATE NOCASE
      LIMIT 20
    ''', <Object?>[like]);
    final ResultSet albumRows = db.select('''
      SELECT COALESCE(NULLIF(TRIM(album), ''), 'Unknown Album') AS name,
             COALESCE(NULLIF(TRIM(artist), ''), 'Unknown Artist') AS artist_name,
             MAX(artwork_hash) AS artwork_hash,
             MAX(artwork_small_path) AS artwork_small_path,
             MAX(artwork_large_path) AS artwork_large_path
      FROM songs
      GROUP BY name, artist_name
      HAVING LOWER(name) LIKE ? ESCAPE '~' OR LOWER(artist_name) LIKE ? ESCAPE '~'
      ORDER BY name COLLATE NOCASE
      LIMIT 20
    ''', <Object?>[like, like]);
    final ResultSet songRows = db.select('''
      SELECT *
      FROM songs
      WHERE LOWER(title) LIKE ? ESCAPE '~'
         OR LOWER(COALESCE(artist, '')) LIKE ? ESCAPE '~'
         OR LOWER(COALESCE(album, '')) LIKE ? ESCAPE '~'
      ORDER BY title COLLATE NOCASE
      LIMIT 50
    ''', <Object?>[like, like, like]);

    return <MusicItem>[
      ...artistRows.map((Row row) => MusicItem(
            id: '$artistIdPrefix${row['name']}',
            title: row['name'] as String,
            isFolder: true,
            type: MusicItemType.artist,
          )),
      ...albumRows.map((Row row) {
        final String artist = row['artist_name'] as String;
        final String album = row['name'] as String;
        return MusicItem(
          id: '$albumIdPrefix${Uri.encodeComponent(artist)}|${Uri.encodeComponent(album)}',
          title: album,
          artist: artist,
          artworkHash: row['artwork_hash'] as String?,
          localArtworkSmallPath: row['artwork_small_path'] as String?,
          localArtworkLargePath: row['artwork_large_path'] as String?,
          isFolder: true,
          type: MusicItemType.album,
        );
      }),
      ...songRows.map(_songFromRow),
    ];
  }

  Future<List<MusicPlaylist>> getPlaylists() async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT p.id,
             p.name,
             COUNT(ps.song_id) AS song_count,
             SUM(COALESCE(s.duration_seconds, 0)) AS duration_seconds
      FROM playlists p
      LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
      LEFT JOIN songs s ON s.id = ps.song_id
      GROUP BY p.id, p.name
      ORDER BY p.name COLLATE NOCASE
    ''');
    return rows
        .map((Row row) => MusicPlaylist(
              id: row['id'] as String,
              name: row['name'] as String,
              songCount: row['song_count'] as int,
              duration: _durationFromSeconds(row['duration_seconds']) ?? Duration.zero,
            ))
        .toList();
  }

  Future<bool> createPlaylist(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final Database db = await database;
    db.execute(
      'INSERT INTO playlists(id, name) VALUES(?, ?)',
      <Object?>['local-playlist-${DateTime.now().microsecondsSinceEpoch}', trimmed],
    );
    return true;
  }

  Future<bool> deletePlaylist(String playlistId) async {
    final Database db = await database;
    db.execute('DELETE FROM playlists WHERE id = ?', <Object?>[playlistId]);
    return true;
  }

  Future<List<MusicItem>> getPlaylistSongs(String playlistId) async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT s.*
      FROM playlist_songs ps
      JOIN songs s ON s.id = ps.song_id
      WHERE ps.playlist_id = ?
      ORDER BY ps.position
    ''', <Object?>[playlistId]);
    return rows.map(_songFromRow).toList();
  }

  Future<bool> addSongToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final int? localSongId = parseSongId(songId);
    if (localSongId == null) return false;
    final Database db = await database;
    final ResultSet positionRows = db.select(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_position FROM playlist_songs WHERE playlist_id = ?',
      <Object?>[playlistId],
    );
    db.execute('INSERT INTO playlist_songs(playlist_id, song_id, position) VALUES(?, ?, ?)',
        <Object?>[playlistId, localSongId, positionRows.first['next_position'] as int]);
    return true;
  }

  Future<bool> removeSongFromPlaylist({
    required String playlistId,
    required int songIndex,
  }) async {
    final Database db = await database;
    final ResultSet rows = db.select(
      'SELECT id FROM playlist_songs WHERE playlist_id = ? ORDER BY position LIMIT 1 OFFSET ?',
      <Object?>[playlistId, songIndex],
    );
    if (rows.isEmpty) return false;
    db.execute('DELETE FROM playlist_songs WHERE id = ?', <Object?>[rows.first['id'] as int]);
    _reorderPlaylist(db, playlistId);
    return true;
  }

  Future<bool> setSongStars({
    required String songId,
    required int starsCount,
  }) async {
    final int? localSongId = parseSongId(songId);
    if (localSongId == null) return false;
    final Database db = await database;
    db.execute('UPDATE songs SET stars_count = ? WHERE id = ?', <Object?>[starsCount.clamp(0, 1), localSongId]);
    return true;
  }

  Future<void> incrementPlayCount(String songId) async {
    final int? localSongId = parseSongId(songId);
    if (localSongId == null) return;
    final Database db = await database;
    db.execute(
      'UPDATE songs SET play_count = play_count + 1, last_played_at = CURRENT_TIMESTAMP WHERE id = ?',
      <Object?>[localSongId],
    );
  }

  Future<List<MusicItem>> getStarredSongs() async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT *
      FROM songs
      WHERE stars_count > 0
      ORDER BY title COLLATE NOCASE
    ''');
    return rows.map(_songFromRow).toList();
  }

  Future<List<MusicItem>> getMostPlayedSongs({int limit = 25}) async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT *
      FROM songs
      WHERE play_count > 0
      ORDER BY play_count DESC, title COLLATE NOCASE
      LIMIT ?
    ''', <Object?>[limit]);
    return rows.map(_songFromRow).toList();
  }

  Future<List<MusicItem>> getRecentlyPlayedSongs({int limit = 25}) async {
    final Database db = await database;
    final ResultSet rows = db.select('''
      SELECT *
      FROM songs
      WHERE last_played_at IS NOT NULL
      ORDER BY last_played_at DESC
      LIMIT ?
    ''', <Object?>[limit]);
    return rows.map(_songFromRow).toList();
  }

  static int? parseSongId(String itemId) {
    if (!itemId.startsWith(songIdPrefix)) return null;
    return int.tryParse(itemId.substring(songIdPrefix.length));
  }

  static String parseFolderId(String itemId) {
    if (!itemId.startsWith(folderIdPrefix)) return itemId;
    return itemId.substring(folderIdPrefix.length);
  }

  static ({String artist, String album}) parseAlbumId(String itemId) {
    final String encoded = itemId.startsWith(albumIdPrefix) ? itemId.substring(albumIdPrefix.length) : itemId;
    final List<String> parts = encoded.split('|');
    return (
      artist: Uri.decodeComponent(parts.isNotEmpty ? parts[0] : 'Unknown Artist'),
      album: Uri.decodeComponent(parts.length > 1 ? parts[1] : 'Unknown Album'),
    );
  }

  static String normalizePath(String path) {
    return p.normalize(path.trim()).replaceAll('/', '\\').toLowerCase();
  }

  void close() {
    _db?.close();
    _db = null;
    _dbCompleter = null;
  }

  MusicItem _songFromRow(Row row) {
    final String path = row['path'] as String;
    final int starsCount = row['stars_count'] as int? ?? 0;
    return MusicItem(
      id: '$songIdPrefix${row['id']}',
      title: row['title'] as String,
      artist: row['artist'] as String?,
      album: row['album'] as String?,
      duration: _durationFromSeconds(row['duration_seconds']),
      streamUrl: Uri.file(path).toString(),
      localPath: path,
      parentPath: row['parent_path'] as String?,
      artworkHash: row['artwork_hash'] as String?,
      localArtworkSmallPath: row['artwork_small_path'] as String?,
      localArtworkLargePath: row['artwork_large_path'] as String?,
      type: MusicItemType.song,
      starred: starsCount > 0,
      starsCount: starsCount,
      playCount: row['play_count'] as int? ?? 0,
    );
  }

  static String? _directChildFolder(String folderPath, String descendantParentPath) {
    final String normalizedFolder = normalizePath(folderPath);
    final String normalizedDescendant = normalizePath(descendantParentPath);
    if (!normalizedDescendant.startsWith('$normalizedFolder\\')) return null;

    final String relative = descendantParentPath.substring(folderPath.length).replaceFirst(RegExp(r'^[\\/]+'), '');
    if (relative.isEmpty) return null;
    final String firstSegment = relative.split(RegExp(r'[\\/]')).first;
    if (firstSegment.isEmpty) return null;
    return p.join(folderPath, firstSegment);
  }

  static String _escapeLike(String value) {
    return value.replaceAll('~', '~~').replaceAll('%', '~%').replaceAll('_', '~_');
  }

  static String sanitize(String input) {
    // Replace non-ASCII characters and special symbols with '-'
    // Keeps: a-z, A-Z, 0-9, _, space, ., -
    String result = input.replaceAll(RegExp(r'[^\x00-\x7F]|[^\w\s\.\-]'), '-');

    // Collapse multiple hyphens and trim them from the ends
    result = result.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-+|-+$'), '').trim();

    return result;
  }

  static String _fallbackTitle(String title, String path) {
    final String trimmed = title.trim();
    String result = sanitize(trimmed.isNotEmpty ? trimmed : p.basenameWithoutExtension(path));

    if (result.isEmpty) {
      return trimmed.isNotEmpty ? trimmed : p.basenameWithoutExtension(path);
    }
    return result;
  }

  static String? _blankToNull(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static Duration? _durationFromSeconds(dynamic raw) {
    final int? seconds = switch (raw) {
      final int value => value,
      final double value => value.round(),
      final String value => int.tryParse(value),
      _ => null,
    };
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  void _reorderPlaylist(Database db, String playlistId) {
    final ResultSet rows = db.select(
      'SELECT id FROM playlist_songs WHERE playlist_id = ? ORDER BY position',
      <Object?>[playlistId],
    );
    db.execute('BEGIN');
    try {
      for (int index = 0; index < rows.length; index++) {
        db.execute(
          'UPDATE playlist_songs SET position = ? WHERE id = ?',
          <Object?>[index, rows[index]['id'] as int],
        );
      }
      db.execute('COMMIT');
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }
}
