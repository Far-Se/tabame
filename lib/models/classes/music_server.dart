import 'dart:convert';

enum MusicServerType { subsonic, jellyfin }

enum MusicItemType { song, artist, album, folder }

Duration? _durationFromSeconds(dynamic raw, {Duration maxDuration = const Duration(hours: 24)}) {
  final int? seconds = switch (raw) {
    final int value => value,
    final double value => value.round(),
    // ignore: unreachable_switch_case
    final num value => value.round(),
    final String value => int.tryParse(value),
    _ => null,
  };

  if (seconds == null || seconds <= 0) return null;
  final Duration duration = Duration(seconds: seconds);
  if (duration > maxDuration) return null;
  return duration;
}

class MusicServerConfig {
  final String id;
  final String name;
  final String url;
  final String username;
  final String password; // Stored as plain or hashed? Subsonic needs the secret to generate token/salt.
  final MusicServerType type;
  final bool isDefault;

  MusicServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.type = MusicServerType.subsonic,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'type': type.index,
      'isDefault': isDefault,
    };
  }

  factory MusicServerConfig.fromMap(Map<String, dynamic> map) {
    return MusicServerConfig(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      type: MusicServerType.values[map['type'] ?? 0],
      isDefault: map['isDefault'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());
  factory MusicServerConfig.fromJson(String source) => MusicServerConfig.fromMap(json.decode(source));
}

class MusicItem {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final String? streamUrl;
  final String? localPath;
  final String? parentPath;
  final String? artworkHash;
  final String? localArtworkSmallPath;
  final String? localArtworkLargePath;
  final bool isFolder;
  final MusicItemType type;
  final bool durationNeedsRefresh;
  final bool starred;
  final int playCount;
  final int starsCount;

  MusicItem({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.streamUrl,
    this.localPath,
    this.parentPath,
    this.artworkHash,
    this.localArtworkSmallPath,
    this.localArtworkLargePath,
    this.isFolder = false,
    this.type = MusicItemType.song,
    this.durationNeedsRefresh = false,
    this.starred = false,
    this.playCount = 0,
    this.starsCount = 0,
  });

  MusicItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    Duration? duration,
    String? streamUrl,
    String? localPath,
    String? parentPath,
    String? artworkHash,
    String? localArtworkSmallPath,
    String? localArtworkLargePath,
    bool? isFolder,
    MusicItemType? type,
    bool? durationNeedsRefresh,
    bool? starred,
    int? playCount,
    int? starsCount,
  }) {
    return MusicItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
      streamUrl: streamUrl ?? this.streamUrl,
      localPath: localPath ?? this.localPath,
      parentPath: parentPath ?? this.parentPath,
      artworkHash: artworkHash ?? this.artworkHash,
      localArtworkSmallPath: localArtworkSmallPath ?? this.localArtworkSmallPath,
      localArtworkLargePath: localArtworkLargePath ?? this.localArtworkLargePath,
      isFolder: isFolder ?? this.isFolder,
      type: type ?? this.type,
      durationNeedsRefresh: durationNeedsRefresh ?? this.durationNeedsRefresh,
      starred: starred ?? this.starred,
      playCount: playCount ?? this.playCount,
      starsCount: starsCount ?? this.starsCount,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'duration': duration?.inSeconds,
      'streamUrl': streamUrl,
      'localPath': localPath,
      'parentPath': parentPath,
      'artworkHash': artworkHash,
      'localArtworkSmallPath': localArtworkSmallPath,
      'localArtworkLargePath': localArtworkLargePath,
      'isFolder': isFolder,
      'type': type.index,
      'durationNeedsRefresh': durationNeedsRefresh,
      'starred': starred,
      'playCount': playCount,
      'starsCount': starsCount,
    };
  }

  factory MusicItem.fromMap(Map<String, dynamic> map) {
    final int starsCount = map['starsCount'] ?? 0;
    return MusicItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      artist: map['artist'],
      album: map['album'],
      coverUrl: map['coverUrl'],
      duration: _durationFromSeconds(map['duration']),
      streamUrl: map['streamUrl'],
      localPath: map['localPath'],
      parentPath: map['parentPath'],
      artworkHash: map['artworkHash'],
      localArtworkSmallPath: map['localArtworkSmallPath'],
      localArtworkLargePath: map['localArtworkLargePath'],
      isFolder: map['isFolder'] ?? false,
      type: MusicItemType.values[map['type'] ?? 0],
      durationNeedsRefresh: map['durationNeedsRefresh'] ?? false,
      starred: (map['starred'] ?? false) || starsCount > 0,
      playCount: map['playCount'] ?? 0,
      starsCount: starsCount,
    );
  }
}

class MusicPlaylist {
  final String id;
  final String name;
  final int songCount;
  final Duration duration;
  final List<MusicItem>? songs;

  MusicPlaylist({
    required this.id,
    required this.name,
    required this.songCount,
    required this.duration,
    this.songs,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'songCount': songCount,
      'duration': duration.inSeconds,
      'songs': songs?.map((MusicItem x) => x.toMap()).toList(),
    };
  }

  factory MusicPlaylist.fromMap(Map<String, dynamic> map) {
    return MusicPlaylist(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      songCount: map['songCount'] ?? 0,
      duration: _durationFromSeconds(map['duration'], maxDuration: const Duration(days: 365)) ?? Duration.zero,
      songs: map['songs'] != null
          ? List<MusicItem>.from(map['songs']?.map((dynamic x) => MusicItem.fromMap(x as Map<String, dynamic>)))
          : null,
    );
  }
}
