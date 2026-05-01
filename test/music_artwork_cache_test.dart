import 'dart:io';
import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:tabame/models/classes/music_server.dart';
import 'package:tabame/models/db/music_library_db.dart';
import 'package:tabame/services/music_artwork_cache.dart';

void main() {
  late Directory tempDir;
  late MusicLibraryDb db;
  late MusicArtworkCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tabame_music_artwork_test_');
    db = MusicLibraryDb.instance;
    db.setDatabasePath(p.join(tempDir.path, 'music_library_test.db'));
    await db.database;
    cache = MusicArtworkCache(
      db: db,
      cacheDirectoryPath: p.join(tempDir.path, 'cache', 'music_artwork'),
    );
  });

  tearDown(() async {
    db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('prefers embedded front cover artwork', () async {
    final File song = File(p.join(tempDir.path, 'song.mp3'))..writeAsStringSync('audio');
    final Uint8List otherBytes = _imageBytes(0xffff0000);
    final Uint8List frontBytes = _imageBytes(0xff0000ff);

    final MusicArtworkRecord? record = await cache.resolveForFile(
      audioFile: song,
      pictures: <Picture>[
        Picture(pictureType: PictureType.other, bytes: otherBytes),
        Picture(pictureType: PictureType.coverFront, bytes: frontBytes),
      ],
    );

    expect(record, isNotNull);
    expect(record!.artworkHash, sha1.convert(frontBytes).toString());
    expect(File(record.smallPath).existsSync(), isTrue);
    expect(File(record.largePath).existsSync(), isTrue);
  });

  test('uses same-folder album or cover image when embedded art is missing', () async {
    final Directory albumFolder = await Directory(p.join(tempDir.path, 'Album')).create();
    final File song = File(p.join(albumFolder.path, 'song.mp3'))..writeAsStringSync('audio');
    final Uint8List coverBytes = _imageBytes(0xff00ff00);
    final File cover = File(p.join(albumFolder.path, 'Cover.JPG'))..writeAsBytesSync(coverBytes);

    final MusicArtworkRecord? record = await cache.resolveForFile(audioFile: song, pictures: null);

    expect(record, isNotNull);
    expect(record!.artworkHash, sha1.convert(coverBytes).toString());
    expect(record.sourcePath, cover.path);
  });

  test('deduplicates identical artwork and creates new records for changed art', () async {
    final File one = File(p.join(tempDir.path, 'one.mp3'))..writeAsStringSync('one');
    final File two = File(p.join(tempDir.path, 'two.mp3'))..writeAsStringSync('two');
    final Uint8List sharedBytes = _imageBytes(0xffaaaaaa);

    final MusicArtworkRecord? first = await cache.resolveForFile(
      audioFile: one,
      pictures: <Picture>[Picture(pictureType: PictureType.coverFront, bytes: sharedBytes)],
    );
    final MusicArtworkRecord? second = await cache.resolveForFile(
      audioFile: two,
      pictures: <Picture>[Picture(pictureType: PictureType.coverFront, bytes: sharedBytes)],
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.smallPath, first!.smallPath);
    expect(second.largePath, first.largePath);
    expect(await _artworkRecordCount(db), 1);

    final Uint8List changedBytes = _imageBytes(0xff111111);
    await cache.resolveForFile(
      audioFile: two,
      pictures: <Picture>[Picture(pictureType: PictureType.coverFront, bytes: changedBytes)],
    );

    expect(await _artworkRecordCount(db), 2);
  });

  test('returns artwork paths on local songs from the database', () async {
    final Directory root = await Directory(p.join(tempDir.path, 'Music')).create();
    final String smallPath = p.join(tempDir.path, 'small.jpg');
    final String largePath = p.join(tempDir.path, 'large.jpg');

    await db.upsertSong(
      LocalMusicMetadata(
        path: p.join(root.path, 'song.mp3'),
        rootPath: root.path,
        parentPath: root.path,
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationSeconds: 60,
        artworkHash: 'hash',
        artworkSmallPath: smallPath,
        artworkLargePath: largePath,
        artworkSourcePath: p.join(root.path, 'song.mp3'),
        artworkSourceModifiedMillis: 1,
        fileSize: 4,
        modifiedMillis: 1,
      ),
      'token',
    );

    final List<MusicItem> items = await db.getDirectoryByPath(root.path);
    final MusicItem song = items.singleWhere((MusicItem item) => !item.isFolder);

    expect(song.artworkHash, 'hash');
    expect(song.localArtworkSmallPath, smallPath);
    expect(song.localArtworkLargePath, largePath);
  });
}

Uint8List _imageBytes(int color) {
  final img.Image image = img.Image(width: 40, height: 40);
  img.fill(image, color: img.ColorRgb8((color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff));
  return Uint8List.fromList(img.encodePng(image));
}

Future<int> _artworkRecordCount(MusicLibraryDb db) async {
  final Database database = await db.database;
  final ResultSet rows = database.select('SELECT COUNT(*) AS total FROM music_artwork');
  return rows.first['total'] as int;
}
