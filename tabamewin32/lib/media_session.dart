import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class MediaSession {
  final String id;
  final bool isCurrent;
  final String title;
  final String artist;
  final String albumTitle;
  final String albumArtist;
  final int trackNumber;
  final String playbackStatus; // "Playing" | "Paused" | "Stopped" | "Changing" | "Closed"
  final bool canPlay;
  final bool canPause;
  final bool canSkipNext;
  final bool canSkipPrevious;

  /// Raw image bytes (JPEG or PNG) as provided by the app to SMTC.
  /// Null if the session has no artwork.
  /// Use directly with [Image.memory] or [MemoryImage].
  final Uint8List? thumbnail;

  const MediaSession({
    required this.id,
    required this.isCurrent,
    required this.title,
    required this.artist,
    required this.albumTitle,
    required this.albumArtist,
    required this.trackNumber,
    required this.playbackStatus,
    required this.canPlay,
    required this.canPause,
    required this.canSkipNext,
    required this.canSkipPrevious,
    this.thumbnail,
  });

  bool get isPlaying => playbackStatus == 'Playing';

  /// Returns an [ImageProvider] for the thumbnail, or null if unavailable.
  ImageProvider? get thumbnailImage => thumbnail != null ? MemoryImage(thumbnail!) : null;

  factory MediaSession.fromMap(Map<Object?, Object?> map) {
    final Object? rawThumb = map['thumbnail'];
    Uint8List? thumb;
    if (rawThumb is Uint8List) {
      thumb = rawThumb;
    } else if (rawThumb is List) {
      thumb = Uint8List.fromList(rawThumb.cast<int>());
    }

    return MediaSession(
      id: map['id'] as String? ?? '',
      isCurrent: map['isCurrent'] as bool? ?? false,
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String? ?? '',
      albumTitle: map['albumTitle'] as String? ?? '',
      albumArtist: map['albumArtist'] as String? ?? '',
      trackNumber: map['trackNumber'] as int? ?? 0,
      playbackStatus: map['playbackStatus'] as String? ?? 'Unknown',
      canPlay: map['canPlay'] as bool? ?? false,
      canPause: map['canPause'] as bool? ?? false,
      canSkipNext: map['canSkipNext'] as bool? ?? false,
      canSkipPrevious: map['canSkipPrevious'] as bool? ?? false,
      thumbnail: thumb,
    );
  }

  @override
  String toString() => 'MediaSession($id: "$title" by $artist [$playbackStatus]'
      '${thumbnail != null ? " +art" : ""})';
}

class MediaSessionResult {
  final String? currentSessionId;
  final List<MediaSession> sessions;

  const MediaSessionResult({
    required this.currentSessionId,
    required this.sessions,
  });

  MediaSession? get currentSession {
    for (final MediaSession session in sessions) {
      if (session.isCurrent) return session;
    }
    return null;
  }
}

class MediaSessionPlugin {
  static const MethodChannel _channel = MethodChannel('tabamewin32');

  /// Returns all SMTC sessions, marking which one is currently active.
  /// Throws a [PlatformException] if the Windows API call fails.
  static Future<MediaSessionResult> getMediaSessions() async {
    final Map<Object?, Object?>? result = await _channel.invokeMethod<Map<Object?, Object?>>('getMediaSessions');
    if (result == null) return const MediaSessionResult(currentSessionId: null, sessions: <MediaSession>[]);

    final List<Object?> rawSessions = result['sessions'] as List<Object?>? ?? <Object?>[];
    final List<MediaSession> sessions =
        rawSessions.whereType<Map<Object?, Object?>>().map(MediaSession.fromMap).toList();

    return MediaSessionResult(
      currentSessionId: result['currentSessionId'] as String?,
      sessions: sessions,
    );
  }
}
