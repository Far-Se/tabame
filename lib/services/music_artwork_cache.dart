import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/db/music_library_db.dart';
import '../models/win32/win_utils.dart';

class MusicArtworkCache {
  MusicArtworkCache({
    MusicLibraryDb? db,
    String? cacheDirectoryPath,
  })  : _db = db ?? MusicLibraryDb.instance,
        _cacheDirectoryPath = cacheDirectoryPath ?? p.join(WinUtils.getTabameAppDataFolder(), 'cache', 'music_artwork');

  static final MusicArtworkCache instance = MusicArtworkCache();

  static const int smallSize = 96;
  static const int largeSize = 256;
  static const int jpegQuality = 82;

  final MusicLibraryDb _db;
  final String _cacheDirectoryPath;

  Future<MusicArtworkRecord?> resolveForFile({
    required File audioFile,
    required List<Picture>? pictures,
  }) async {
    final _ArtworkSource? source = await _findArtworkSource(audioFile: audioFile, pictures: pictures);
    if (source == null || source.bytes.isEmpty) return null;

    final String hash = sha1.convert(source.bytes).toString();
    final MusicArtworkRecord? existing = await _db.getArtworkRecord(hash);
    if (existing != null && File(existing.smallPath).existsSync() && File(existing.largePath).existsSync()) {
      return existing;
    }

    final img.Image? decoded = img.decodeImage(source.bytes);
    if (decoded == null) return null;

    final Directory cacheDirectory = Directory(_cacheDirectoryPath);
    if (!cacheDirectory.existsSync()) cacheDirectory.createSync(recursive: true);

    final String smallPath = p.join(cacheDirectory.path, '$hash-$smallSize.jpg');
    final String largePath = p.join(cacheDirectory.path, '$hash-$largeSize.jpg');

    _writeThumbnail(decoded, smallPath, smallSize);
    _writeThumbnail(decoded, largePath, largeSize);

    final MusicArtworkRecord record = MusicArtworkRecord(
      artworkHash: hash,
      smallPath: smallPath,
      largePath: largePath,
      sourcePath: source.path,
      sourceModifiedMillis: source.modifiedMillis,
    );
    await _db.upsertArtworkRecord(record);
    return record;
  }

  static Picture? selectEmbeddedPicture(List<Picture>? pictures) {
    if (pictures == null || pictures.isEmpty) return null;
    for (final Picture picture in pictures) {
      if (picture.pictureType == PictureType.coverFront && picture.bytes.isNotEmpty) return picture;
    }
    for (final Picture picture in pictures) {
      if (picture.bytes.isNotEmpty) return picture;
    }
    return null;
  }

  static Future<File?> findFolderArtworkFile(Directory directory) async {
    if (!await directory.exists()) return null;

    final Map<String, File> candidates = <String, File>{};
    try {
      await for (final FileSystemEntity entity in directory.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;
        candidates[p.basename(entity.path).toLowerCase()] = entity;
      }
    } catch (_) {
      return null;
    }

    const List<String> names = <String>['album', 'cover', 'Folder', 'folder'];
    const List<String> extensions = <String>['.png', '.jpg', '.jpeg'];
    for (final String name in names) {
      for (final String extension in extensions) {
        final File? file = candidates['$name$extension'];
        if (file != null) return file;
      }
    }
    return null;
  }

  Future<_ArtworkSource?> _findArtworkSource({
    required File audioFile,
    required List<Picture>? pictures,
  }) async {
    final Picture? embedded = selectEmbeddedPicture(pictures);
    if (embedded != null) {
      final FileStat stat = await audioFile.stat();
      return _ArtworkSource(
        bytes: embedded.bytes,
        path: audioFile.path,
        modifiedMillis: stat.modified.millisecondsSinceEpoch,
      );
    }

    final File? folderArtwork = await findFolderArtworkFile(audioFile.parent);
    if (folderArtwork == null) return null;

    try {
      final FileStat stat = await folderArtwork.stat();
      return _ArtworkSource(
        bytes: await folderArtwork.readAsBytes(),
        path: folderArtwork.path,
        modifiedMillis: stat.modified.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('MusicArtworkCache: could not read ${folderArtwork.path}: $e');
      return null;
    }
  }

  static void _writeThumbnail(img.Image decoded, String targetPath, int size) {
    final File target = File(targetPath);
    if (target.existsSync()) return;

    final img.Image thumbnail = img.copyResizeCropSquare(
      decoded,
      size: size,
      interpolation: img.Interpolation.average,
    );
    target.writeAsBytesSync(img.encodeJpg(thumbnail, quality: jpegQuality), flush: false);
  }
}

class _ArtworkSource {
  const _ArtworkSource({
    required this.bytes,
    required this.path,
    required this.modifiedMillis,
  });

  final Uint8List bytes;
  final String path;
  final int modifiedMillis;
}
