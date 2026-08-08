import 'dart:typed_data';

/// The two endpoint directions exposed by the shared audio contract.
enum AudioDeviceType {
  output,
  input,
}

/// A device snapshot with an adapter-owned opaque identifier.
///
/// Device identifiers are runtime values. Callers must not persist them or
/// interpret them as a native handle, index, or OS-specific object.
class PlatformAudioDevice {
  const PlatformAudioDevice({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
    this.iconBytes,
  });

  final String id;
  final String name;
  final bool isDefault;
  final bool isActive;
  final Uint8List? iconBytes;
}

/// A process or stream-level volume entry when the platform exposes one.
///
/// [id] is opaque and owned by the adapter. [processId] is optional diagnostic
/// metadata only; it is never used as a window identity.
class PlatformAudioProcess {
  const PlatformAudioProcess({
    required this.id,
    this.processId = 0,
    this.applicationName = '',
    this.processPath = '',
    this.volume = 1.0,
    this.peakVolume = 0.0,
    this.iconBytes,
  });

  final String id;
  final int processId;
  final String applicationName;
  final String processPath;
  final double volume;
  final double peakVolume;
  final Uint8List? iconBytes;

  /// Compatibility terminology used by the existing mixer UI.
  double get maxVolume => volume;

  String get displayName {
    if (applicationName.trim().isNotEmpty) return applicationName;
    if (processPath.trim().isNotEmpty) {
      final String normalized = processPath.replaceAll('\\', '/');
      return normalized.split('/').last;
    }
    return id;
  }

  PlatformAudioProcess copyWith({
    String? id,
    int? processId,
    String? applicationName,
    String? processPath,
    double? volume,
    double? peakVolume,
    Uint8List? iconBytes,
  }) {
    return PlatformAudioProcess(
      id: id ?? this.id,
      processId: processId ?? this.processId,
      applicationName: applicationName ?? this.applicationName,
      processPath: processPath ?? this.processPath,
      volume: volume ?? this.volume,
      peakVolume: peakVolume ?? this.peakVolume,
      iconBytes: iconBytes ?? this.iconBytes,
    );
  }
}

/// One endpoint's data, assembled by the shared orchestration layer.
class AudioEndpointSnapshot {
  const AudioEndpointSnapshot({
    required this.type,
    required this.devices,
    required this.defaultDevice,
    required this.volume,
    required this.isMuted,
    required this.deviceVolumes,
  });

  final AudioDeviceType type;
  final List<PlatformAudioDevice> devices;
  final PlatformAudioDevice? defaultDevice;
  final double volume;
  final bool isMuted;
  final Map<String, double> deviceVolumes;

  bool get hasDevices => devices.isNotEmpty;
}

/// Shared selection flags retained for Windows role compatibility.
///
/// Linux and macOS adapters may ignore individual role flags when their audio
/// stack exposes one default endpoint per direction.
class AudioDeviceTargeting {
  const AudioDeviceTargeting({
    this.console = false,
    this.multimedia = true,
    this.communications = false,
  });

  final bool console;
  final bool multimedia;
  final bool communications;
}

/// Transport operations understood by the media-session contract.
enum PlatformMediaCommand {
  playPause,
  play,
  pause,
  next,
  previous,
  seekForward,
  seekBackward,
}

extension PlatformMediaCommandWireName on PlatformMediaCommand {
  String get wireName => switch (this) {
        PlatformMediaCommand.playPause => 'togglePlayPause',
        PlatformMediaCommand.play => 'play',
        PlatformMediaCommand.pause => 'pause',
        PlatformMediaCommand.next => 'skipNext',
        PlatformMediaCommand.previous => 'skipPrevious',
        PlatformMediaCommand.seekForward => 'seekForward',
        PlatformMediaCommand.seekBackward => 'seekBackward',
      };
}

/// Neutral metadata for one application media session.
class PlatformMediaSession {
  const PlatformMediaSession({
    required this.id,
    required this.isCurrent,
    required this.title,
    required this.artist,
    this.albumTitle = '',
    this.albumArtist = '',
    this.trackNumber = 0,
    this.playbackStatus = 'Unknown',
    this.canPlay = false,
    this.canPause = false,
    this.canSkipNext = false,
    this.canSkipPrevious = false,
    this.applicationName = '',
    this.artworkBytes,
    this.artworkUrl = '',
  });

  final String id;
  final bool isCurrent;
  final String title;
  final String artist;
  final String albumTitle;
  final String albumArtist;
  final int trackNumber;
  final String playbackStatus;
  final bool canPlay;
  final bool canPause;
  final bool canSkipNext;
  final bool canSkipPrevious;
  final String applicationName;
  final Uint8List? artworkBytes;
  final String artworkUrl;

  bool get isPlaying => playbackStatus.toLowerCase() == 'playing';
}

class PlatformMediaSessionResult {
  const PlatformMediaSessionResult({
    required this.currentSessionId,
    required this.sessions,
  });

  final String? currentSessionId;
  final List<PlatformMediaSession> sessions;

  PlatformMediaSession? get currentSession {
    for (final PlatformMediaSession session in sessions) {
      if (session.isCurrent) return session;
    }
    if (currentSessionId != null) {
      for (final PlatformMediaSession session in sessions) {
        if (session.id == currentSessionId) return session;
      }
    }
    return null;
  }
}

/// Binding data for a configured application media control.
///
/// The binding is interpreted by the platform adapter. Shared widgets never
/// search for a window, tray item, or native identifier themselves.
class PlatformMediaBinding {
  const PlatformMediaBinding({
    required this.applicationId,
    this.applicationPath = '',
    this.hotkeyForward = '',
    this.hotkeyRewind = '',
    this.hotkeyNext = '',
    this.hotkeyPrevious = '',
    this.hotkeyPlayPause = '',
  });

  final String applicationId;
  final String applicationPath;
  final String hotkeyForward;
  final String hotkeyRewind;
  final String hotkeyNext;
  final String hotkeyPrevious;
  final String hotkeyPlayPause;

  String hotkeyFor(PlatformMediaCommand command) => switch (command) {
        PlatformMediaCommand.seekForward => hotkeyForward,
        PlatformMediaCommand.seekBackward => hotkeyRewind,
        PlatformMediaCommand.next => hotkeyNext,
        PlatformMediaCommand.previous => hotkeyPrevious,
        PlatformMediaCommand.playPause => hotkeyPlayPause,
        PlatformMediaCommand.play => hotkeyPlayPause,
        PlatformMediaCommand.pause => hotkeyPlayPause,
      };
}

/// Contract for system output/input control and optional per-process mixing.
abstract class AudioSystemService {
  const AudioSystemService();

  static AudioSystemService _instance = const UnavailableAudioSystemService();

  static AudioSystemService get instance => _instance;

  static void register(AudioSystemService service) {
    _instance = service;
  }

  bool get isAvailable;
  String get unavailableReason;
  bool get supportsPerProcessAudio => false;
  bool get supportsSystemSettings => false;
  bool get supportsMixerSettings => false;

  /// Initializes or probes the adapter. Implementations must be idempotent.
  Future<bool> initialize() async => isAvailable;

  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async => const <PlatformAudioDevice>[];

  Future<PlatformAudioDevice?> getDefaultDevice(AudioDeviceType type) async {
    final List<PlatformAudioDevice> devices = await listDevices(type);
    for (final PlatformAudioDevice device in devices) {
      if (device.isDefault) return device;
    }
    return devices.isEmpty ? null : devices.first;
  }

  Future<double> getVolume(AudioDeviceType type) async => 0.0;
  Future<bool> setVolume(AudioDeviceType type, double volume) async => false;
  Future<bool> getMute(AudioDeviceType type) async => false;
  Future<bool> setMute(AudioDeviceType type, bool muted) async => false;

  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) async =>
      false;

  Future<bool> switchDefaultDevice(
    AudioDeviceType type, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) async =>
      false;

  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) async => 0.0;

  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) async => false;

  Future<List<PlatformAudioProcess>> listProcesses() async => const <PlatformAudioProcess>[];

  Future<bool> setProcessVolume(String processId, double volume) async => false;

  Future<bool> openSystemSettings() async => false;

  Future<bool> openMixerSettings() async => false;

  Future<bool> adjustVolume(AudioDeviceType type, double delta) async {
    final double current = await getVolume(type);
    return setVolume(type, normalizeVolume(current + delta));
  }

  static double normalizeVolume(double volume) => volume.clamp(0.0, 1.0).toDouble();
}

class UnavailableAudioSystemService extends AudioSystemService {
  const UnavailableAudioSystemService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'System audio controls are unavailable on this platform.';
}

/// Contract for system media sessions and configured application transport.
abstract class MediaSessionService {
  const MediaSessionService();

  static MediaSessionService _instance = const UnavailableMediaSessionService();

  static MediaSessionService get instance => _instance;

  static void register(MediaSessionService service) {
    _instance = service;
  }

  bool get isAvailable;
  String get unavailableReason;
  bool get supportsApplicationControls => false;

  Future<bool> initialize() async => isAvailable;

  Future<PlatformMediaSessionResult> listSessions() async =>
      const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);

  Future<bool> sendCommand(PlatformMediaSession session, PlatformMediaCommand command) async => false;

  Future<bool> sendGlobalCommand(PlatformMediaCommand command) async => false;

  Future<bool> sendApplicationCommand(PlatformMediaBinding binding, PlatformMediaCommand command) async => false;

  Future<bool> isApplicationPlaying(PlatformMediaBinding binding) async => false;

  Future<bool> launchApplication(PlatformMediaBinding binding) async => false;
}

class UnavailableMediaSessionService extends MediaSessionService {
  const UnavailableMediaSessionService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Media sessions are unavailable on this platform.';
}

/// Shared endpoint orchestration extracted from the original Windows facade.
///
/// This class owns normalized values, endpoint snapshots, and toggle/cycle
/// sequencing. Native adapters only implement the contract primitives.
class AudioOrchestrator {
  AudioOrchestrator({AudioSystemService? service}) : service = service ?? AudioSystemService.instance;

  final AudioSystemService service;

  Future<AudioEndpointSnapshot> readEndpoint(AudioDeviceType type) async {
    final List<PlatformAudioDevice> devices = await service.listDevices(type);
    final PlatformAudioDevice? defaultDevice = await service.getDefaultDevice(type);
    final double volume = devices.isEmpty ? 0.0 : AudioSystemService.normalizeVolume(await service.getVolume(type));
    final bool muted = devices.isEmpty ? false : await service.getMute(type);
    final Map<String, double> deviceVolumes = <String, double>{};
    for (final PlatformAudioDevice device in devices) {
      deviceVolumes[device.id] = AudioSystemService.normalizeVolume(await service.getDeviceVolume(type, device.id));
    }
    return AudioEndpointSnapshot(
      type: type,
      devices: devices,
      defaultDevice: defaultDevice,
      volume: volume,
      isMuted: muted,
      deviceVolumes: deviceVolumes,
    );
  }

  Future<bool> toggleMute(AudioDeviceType type) async {
    final bool muted = await service.getMute(type);
    return service.setMute(type, !muted);
  }

  Future<bool> setVolume(AudioDeviceType type, double volume) {
    return service.setVolume(type, AudioSystemService.normalizeVolume(volume));
  }

  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) {
    return service.setDeviceVolume(type, deviceId, AudioSystemService.normalizeVolume(volume));
  }
}
