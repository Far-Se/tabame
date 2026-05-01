import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/models/classes/music_server.dart';
import 'package:tabame/models/db/music_library_db.dart';
import 'package:tabame/services/music_local_indexer.dart';

void main() {
  late Directory tempDir;
  late MusicLibraryDb db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tabame_music_library_test_');
    db = MusicLibraryDb.instance;
    db.setDatabasePath(p.join(tempDir.path, 'music_library_test.db'));
    await db.database;
  });

  tearDown(() async {
    db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('saves and lists local music roots', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();

    await db.addRoot(root.path);

    final List<MusicRoot> roots = await db.getRoots();
    expect(roots, hasLength(1));
    expect(roots.single.path, root.path);
  });

  test('reindex preserves stars, play counts, and song identity by path', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final File song = File(p.join(root.path, 'track.mp3'))..writeAsStringSync('audio');
    final _FakeMetadataReader reader = _FakeMetadataReader(<String, _FakeTrack>{
      song.path: const _FakeTrack(title: 'First Title', artist: 'Artist', album: 'Album'),
    });
    final MusicLocalIndexer indexer = MusicLocalIndexer(db: db, metadataReader: reader);

    await db.addRoot(root.path);
    await indexer.reindexAll();
    final List<MusicItem> firstSongs = await db.getDirectoryByPath(root.path);
    expect(firstSongs.where((MusicItem item) => !item.isFolder), hasLength(1));
    final MusicItem first = firstSongs.firstWhere((MusicItem item) => !item.isFolder);

    await db.setSongStars(songId: first.id, starsCount: 1);
    await db.incrementPlayCount(first.id);
    reader.tracks[song.path] = const _FakeTrack(title: 'Second Title', artist: 'Artist', album: 'Album');

    await indexer.reindexAll();
    final List<MusicItem> reindexedSongs = await db.getDirectoryByPath(root.path);
    final MusicItem reindexed = reindexedSongs.firstWhere((MusicItem item) => !item.isFolder);

    expect(reindexed.id, first.id);
    expect(reindexed.title, 'Second Title');
    expect(reindexed.starsCount, 1);
    expect(reindexed.playCount, 1);
  });

  test('folder reindex removes missing songs only inside the current folder', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final Directory sub = await Directory(p.join(root.path, 'Sub')).create();
    final File rootSong = File(p.join(root.path, 'root.mp3'))..writeAsStringSync('root');
    final File subSong = File(p.join(sub.path, 'sub.mp3'))..writeAsStringSync('sub');
    final MusicLocalIndexer indexer = MusicLocalIndexer(
      db: db,
      metadataReader: _FakeMetadataReader(<String, _FakeTrack>{
        rootSong.path: const _FakeTrack(title: 'Root Song', artist: 'Artist', album: 'Album'),
        subSong.path: const _FakeTrack(title: 'Sub Song', artist: 'Artist', album: 'Album'),
      }),
    );

    await db.addRoot(root.path);
    await indexer.reindexAll();
    expect(await db.countSongs(), 2);

    await subSong.delete();
    await indexer.reindexFolder(sub.path);

    expect(await db.countSongs(), 1);
    final List<MusicItem> rootItems = await db.getDirectoryByPath(root.path);
    expect(rootItems.any((MusicItem item) => item.title == 'Root Song'), isTrue);
    expect(rootItems.any((MusicItem item) => item.title == 'Sub Song'), isFalse);
  });

  test('local playlists keep order and respond to removal', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final File one = File(p.join(root.path, 'one.mp3'))..writeAsStringSync('one');
    final File two = File(p.join(root.path, 'two.mp3'))..writeAsStringSync('two');
    final MusicLocalIndexer indexer = MusicLocalIndexer(
      db: db,
      metadataReader: _FakeMetadataReader(<String, _FakeTrack>{
        one.path: const _FakeTrack(title: 'One', artist: 'Artist', album: 'Album', trackIndex: 1),
        two.path: const _FakeTrack(title: 'Two', artist: 'Artist', album: 'Album', trackIndex: 2),
      }),
    );

    await db.addRoot(root.path);
    await indexer.reindexAll();
    final List<MusicItem> songs =
        (await db.getDirectoryByPath(root.path)).where((MusicItem item) => !item.isFolder).toList(growable: false);
    final MusicItem songOne = songs.firstWhere((MusicItem item) => item.title == 'One');
    final MusicItem songTwo = songs.firstWhere((MusicItem item) => item.title == 'Two');

    expect(await db.createPlaylist('Mix'), isTrue);
    final MusicPlaylist playlist = (await db.getPlaylists()).single;
    expect(await db.addSongToPlaylist(playlistId: playlist.id, songId: songTwo.id), isTrue);
    expect(await db.addSongToPlaylist(playlistId: playlist.id, songId: songOne.id), isTrue);

    List<MusicItem> playlistSongs = await db.getPlaylistSongs(playlist.id);
    expect(playlistSongs.map((MusicItem item) => item.title), <String>['Two', 'One']);

    expect(await db.removeSongFromPlaylist(playlistId: playlist.id, songIndex: 0), isTrue);
    playlistSongs = await db.getPlaylistSongs(playlist.id);
    expect(playlistSongs.map((MusicItem item) => item.title), <String>['One']);
  });

  test('folder rows use first direct song artwork as poster', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final Directory album = await Directory(p.join(root.path, 'Album')).create();
    final File first = File(p.join(album.path, '01 first.mp3'))..writeAsStringSync('first');
    final File second = File(p.join(album.path, '02 second.mp3'))..writeAsStringSync('second');
    final MusicLocalIndexer indexer = MusicLocalIndexer(
      db: db,
      metadataReader: _FakeMetadataReader(<String, _FakeTrack>{
        first.path: const _FakeTrack(
          title: 'First',
          artist: 'Artist',
          album: 'Album',
          trackIndex: 1,
          artworkHash: 'first-hash',
          artworkSmallPath: r'C:\cache\first-small.jpg',
          artworkLargePath: r'C:\cache\first-large.jpg',
        ),
        second.path: const _FakeTrack(
          title: 'Second',
          artist: 'Artist',
          album: 'Album',
          trackIndex: 2,
          artworkHash: 'second-hash',
          artworkSmallPath: r'C:\cache\second-small.jpg',
          artworkLargePath: r'C:\cache\second-large.jpg',
        ),
      }),
    );

    await db.addRoot(root.path);
    await indexer.reindexAll();

    final MusicItem folder =
        (await db.getDirectoryByPath(root.path)).firstWhere((MusicItem item) => item.isFolder && item.title == 'Album');
    expect(folder.artworkHash, 'first-hash');
    expect(folder.localArtworkSmallPath, r'C:\cache\first-small.jpg');
    expect(folder.localArtworkLargePath, r'C:\cache\first-large.jpg');
  });

  test('folder rows use folder artwork file when no direct song artwork exists', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final Directory album = await Directory(p.join(root.path, 'Album')).create();
    final Directory disc = await Directory(p.join(album.path, 'Disc 1')).create();
    final File cover = File(p.join(album.path, 'Cover.JPG'))..writeAsStringSync('cover');
    final File song = File(p.join(disc.path, 'track.mp3'))..writeAsStringSync('song');
    final MusicLocalIndexer indexer = MusicLocalIndexer(
      db: db,
      metadataReader: _FakeMetadataReader(<String, _FakeTrack>{
        song.path: const _FakeTrack(title: 'Track', artist: 'Artist', album: 'Album'),
      }),
    );

    await db.addRoot(root.path);
    await indexer.reindexAll();

    final MusicItem folder =
        (await db.getDirectoryByPath(root.path)).firstWhere((MusicItem item) => item.isFolder && item.title == 'Album');
    expect(folder.artworkHash, isNull);
    expect(folder.localArtworkSmallPath, cover.path);
    expect(folder.localArtworkLargePath, cover.path);
  });
}

class _FakeTrack {
  const _FakeTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.trackIndex,
    this.artworkHash,
    this.artworkSmallPath,
    this.artworkLargePath,
  });

  final String title;
  final String artist;
  final String album;
  final int? trackIndex;
  final String? artworkHash;
  final String? artworkSmallPath;
  final String? artworkLargePath;
}

class _FakeMetadataReader implements MusicMetadataReader {
  _FakeMetadataReader(this.tracks);

  final Map<String, _FakeTrack> tracks;

  @override
  Future<LocalMusicMetadata> read(File file, {required String rootPath}) async {
    final FileStat stat = await file.stat();
    final _FakeTrack track =
        tracks[file.path] ?? _FakeTrack(title: p.basenameWithoutExtension(file.path), artist: 'Artist', album: 'Album');
    return LocalMusicMetadata(
      path: file.path,
      rootPath: rootPath,
      parentPath: p.dirname(file.path),
      title: track.title,
      artist: track.artist,
      album: track.album,
      trackIndex: track.trackIndex,
      durationSeconds: 60,
      artworkHash: track.artworkHash,
      artworkSmallPath: track.artworkSmallPath,
      artworkLargePath: track.artworkLargePath,
      fileSize: stat.size,
      modifiedMillis: stat.modified.millisecondsSinceEpoch,
    );
  }
}
