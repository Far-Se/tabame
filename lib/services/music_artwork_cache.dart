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

  /// Ignore absurdly large embedded/folder art. Decoding a multi-hundred-MB
  /// image would pin memory and CPU even on a background isolate, and it is
  /// almost always a sign of a corrupt tag rather than real cover art.
  static const int maxArtworkSourceBytes = 32 * 1024 * 1024;

  final MusicLibraryDb _db;
  final String _cacheDirectoryPath;

  Future<MusicArtworkRecord?> resolveForFile({
    required File audioFile,
    required List<Picture>? pictures,
  }) async {
    final _ArtworkSource? source = await _findArtworkSource(audioFile: audioFile, pictures: pictures);
    if (source == null || source.bytes.isEmpty) return null;
    if (source.bytes.length > maxArtworkSourceBytes) {
      debugPrint('MusicArtworkCache: skipping oversized artwork (${source.bytes.length} bytes) for ${source.path}');
      return null;
    }

    final String hash = sha1.convert(source.bytes).toString();
    final MusicArtworkRecord? existing = await _db.getArtworkRecord(hash);
    if (existing != null && File(existing.smallPath).existsSync() && File(existing.largePath).existsSync()) {
      return existing;
    }

    final Directory cacheDirectory = Directory(_cacheDirectoryPath);
    if (!cacheDirectory.existsSync()) cacheDirectory.createSync(recursive: true);

    final String smallPath = p.join(cacheDirectory.path, '$hash-$smallSize.jpg');
    final String largePath = p.join(cacheDirectory.path, '$hash-$largeSize.jpg');

    final File smallFile = File(smallPath);
    final File largeFile = File(largePath);
    if (!smallFile.existsSync() || !largeFile.existsSync()) {
      // Decode + resize + re-encode is the single heaviest step of indexing and
      // is pure-Dart CPU work. Run it on a background isolate so a large library
      // can't freeze the UI thread (and the rest of the PC) while indexing.
      _ThumbnailBytes? thumbnails;
      try {
        thumbnails = await compute(
          _buildThumbnails,
          _ThumbnailRequest(bytes: source.bytes, smallSize: smallSize, largeSize: largeSize, quality: jpegQuality),
        );
      } catch (e) {
        debugPrint('MusicArtworkCache: thumbnail generation failed for ${source.path}: $e');
        return null;
      }
      if (thumbnails == null) return null;
      if (!smallFile.existsSync()) await smallFile.writeAsBytes(thumbnails.small, flush: false);
      if (!largeFile.existsSync()) await largeFile.writeAsBytes(thumbnails.large, flush: false);
    }

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

  /// Runs on a background isolate via [compute]. Must stay a pure, top-level
  /// style static function (no `this`) so it is safely sendable.
  static _ThumbnailBytes? _buildThumbnails(_ThumbnailRequest request) {
    final img.Image? decoded = img.decodeImage(request.bytes);
    if (decoded == null) return null;

    final img.Image small = img.copyResizeCropSquare(
      decoded,
      size: request.smallSize,
      interpolation: img.Interpolation.average,
    );
    final img.Image large = img.copyResizeCropSquare(
      decoded,
      size: request.largeSize,
      interpolation: img.Interpolation.average,
    );
    return _ThumbnailBytes(
      small: img.encodeJpg(small, quality: request.quality),
      large: img.encodeJpg(large, quality: request.quality),
    );
  }
}

class _ThumbnailRequest {
  const _ThumbnailRequest({
    required this.bytes,
    required this.smallSize,
    required this.largeSize,
    required this.quality,
  });

  final Uint8List bytes;
  final int smallSize;
  final int largeSize;
  final int quality;
}

class _ThumbnailBytes {
  const _ThumbnailBytes({required this.small, required this.large});

  final Uint8List small;
  final Uint8List large;
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
