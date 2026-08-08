import 'dart:io';
import 'dart:typed_data';

import '../audio_system_service.dart';

import '../../models/win32/keys.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import 'tabamewin32_api.dart' as native;

/// Injectable Windows audio boundary used by [WindowsAudioService].
///
/// The concrete implementation below is the only place in the shared Dart
/// graph that translates the legacy `tabamewin32` audio DTOs into neutral
/// models. Tests can use this boundary without loading the Windows channel.
abstract class WindowsAudioBackend {
  bool get isAvailable;

  Future<bool> initialize() async => isAvailable;

  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async => const <PlatformAudioDevice>[];

  Future<PlatformAudioDevice?> getDefaultDevice(AudioDeviceType type) async => null;

  Future<double> getVolume(AudioDeviceType type) async => 0.0;

  Future<bool> setVolume(AudioDeviceType type, double volume) async => false;

  Future<bool> getMute(AudioDeviceType type) async => false;

  Future<bool> setMute(AudioDeviceType type, bool muted) async => false;

  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    required AudioDeviceTargeting targeting,
  }) async =>
      false;

  Future<bool> switchDefaultDevice(
    AudioDeviceType type, {
    required AudioDeviceTargeting targeting,
  }) async =>
      false;

  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) async => 0.0;

  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) async => false;

  Future<List<PlatformAudioProcess>> listProcesses() async => const <PlatformAudioProcess>[];

  Future<bool> setProcessVolume(String processId, double volume) async => false;

  Future<bool> openSystemSettings() async => false;

  Future<bool> openMixerSettings() async => false;
}

/// Windows adapter for default-device, mute, volume, and session-mixer APIs.
class WindowsAudioService extends AudioSystemService {
  WindowsAudioService({WindowsAudioBackend? backend}) : backend = backend ?? NativeWindowsAudioBackend();

  static final WindowsAudioService instance = WindowsAudioService();

  final WindowsAudioBackend backend;

  @override
  bool get isAvailable => backend.isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'The Windows audio endpoint service is unavailable.';

  @override
  bool get supportsPerProcessAudio => isAvailable;

  @override
  bool get supportsSystemSettings => isAvailable;

  @override
  bool get supportsMixerSettings => isAvailable;

  @override
  Future<bool> initialize() => backend.initialize();

  @override
  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) => backend.listDevices(type);

  @override
  Future<PlatformAudioDevice?> getDefaultDevice(AudioDeviceType type) => backend.getDefaultDevice(type);

  @override
  Future<double> getVolume(AudioDeviceType type) => backend.getVolume(type);

  @override
  Future<bool> setVolume(AudioDeviceType type, double volume) =>
      backend.setVolume(type, AudioSystemService.normalizeVolume(volume));

  @override
  Future<bool> getMute(AudioDeviceType type) => backend.getMute(type);

  @override
  Future<bool> setMute(AudioDeviceType type, bool muted) => backend.setMute(type, muted);

  @override
  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) =>
      backend.setDefaultDevice(type, deviceId, targeting: targeting);

  @override
  Future<bool> switchDefaultDevice(
    AudioDeviceType type, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) =>
      backend.switchDefaultDevice(type, targeting: targeting);

  @override
  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) => backend.getDeviceVolume(type, deviceId);

  @override
  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) =>
      backend.setDeviceVolume(type, deviceId, AudioSystemService.normalizeVolume(volume));

  @override
  Future<List<PlatformAudioProcess>> listProcesses() => backend.listProcesses();

  @override
  Future<bool> setProcessVolume(String processId, double volume) =>
      backend.setProcessVolume(processId, AudioSystemService.normalizeVolume(volume));

  @override
  Future<bool> openSystemSettings() => backend.openSystemSettings();

  @override
  Future<bool> openMixerSettings() => backend.openMixerSettings();
}

/// Injectable Windows media-session boundary used by [WindowsMediaSessionService].
abstract class WindowsMediaBackend {
  bool get isAvailable;

  Future<bool> initialize() async => isAvailable;

  Future<PlatformMediaSessionResult> listSessions() async =>
      const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);

  Future<bool> sendCommand(String sessionId, PlatformMediaCommand command) async => false;

  Future<bool> sendGlobalCommand(PlatformMediaCommand command) async => false;

  Future<bool> sendApplicationCommand(PlatformMediaBinding binding, PlatformMediaCommand command) async => false;

  Future<bool> isApplicationPlaying(PlatformMediaBinding binding) async => false;

  Future<bool> launchApplication(PlatformMediaBinding binding) async => false;
}

/// Windows adapter for SMTC and configured application transport controls.
class WindowsMediaSessionService extends MediaSessionService {
  WindowsMediaSessionService({WindowsMediaBackend? backend}) : backend = backend ?? NativeWindowsMediaBackend();

  static final WindowsMediaSessionService instance = WindowsMediaSessionService();

  final WindowsMediaBackend backend;

  @override
  bool get isAvailable => backend.isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : 'Windows media sessions are unavailable.';

  @override
  bool get supportsApplicationControls => isAvailable;

  @override
  Future<bool> initialize() => backend.initialize();

  @override
  Future<PlatformMediaSessionResult> listSessions() => backend.listSessions();

  @override
  Future<bool> sendCommand(PlatformMediaSession session, PlatformMediaCommand command) =>
      backend.sendCommand(session.id, command);

  @override
  Future<bool> sendGlobalCommand(PlatformMediaCommand command) => backend.sendGlobalCommand(command);

  @override
  Future<bool> sendApplicationCommand(PlatformMediaBinding binding, PlatformMediaCommand command) =>
      backend.sendApplicationCommand(binding, command);

  @override
  Future<bool> isApplicationPlaying(PlatformMediaBinding binding) => backend.isApplicationPlaying(binding);

  @override
  Future<bool> launchApplication(PlatformMediaBinding binding) => backend.launchApplication(binding);
}

/// Legacy Windows bridge implementation. Native handles and Windows DTOs stay
/// inside this adapter; callers receive only neutral models.
class NativeWindowsAudioBackend implements WindowsAudioBackend, WindowsMediaBackend {
  NativeWindowsAudioBackend();

  bool _audioAvailable = false;
  bool _mediaAvailable = false;

  @override
  bool get isAvailable => _audioAvailable;

  bool get isMediaAvailable => _mediaAvailable;

  @override
  Future<bool> initialize() async {
    if (!Platform.isWindows) return false;
    try {
      _audioAvailable = await native.Audio.detectAudioSupport(native.AudioDeviceType.output);
    } catch (_) {
      _audioAvailable = false;
    }
    try {
      await native.MediaSessionPlugin.getMediaSessions();
      _mediaAvailable = true;
    } catch (_) {
      _mediaAvailable = false;
    }
    return _audioAvailable;
  }

  Future<bool> _ensureAudio() async {
    if (_audioAvailable) return true;
    return initialize();
  }

  @override
  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async {
    if (!await _ensureAudio()) return const <PlatformAudioDevice>[];
    try {
      final List<native.AudioDevice> devices =
          await native.Audio.enumDevices(_nativeType(type)) ?? <native.AudioDevice>[];
      return <PlatformAudioDevice>[
        for (final native.AudioDevice device in devices)
          PlatformAudioDevice(
            id: device.id,
            name: device.name,
            isDefault: device.isActive,
            isActive: device.isActive,
            iconBytes: await _iconBytes(device),
          ),
      ];
    } catch (_) {
      return const <PlatformAudioDevice>[];
    }
  }

  @override
  Future<PlatformAudioDevice?> getDefaultDevice(AudioDeviceType type) async {
    if (!await _ensureAudio()) return null;
    try {
      final native.AudioDevice? device = await native.Audio.getDefaultDevice(_nativeType(type));
      if (device == null || device.id.isEmpty) return null;
      return PlatformAudioDevice(
        id: device.id,
        name: device.name,
        isDefault: true,
        isActive: device.isActive,
        iconBytes: await _iconBytes(device),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double> getVolume(AudioDeviceType type) async {
    if (!await _ensureAudio()) return 0.0;
    try {
      return AudioSystemService.normalizeVolume(await native.Audio.getVolume(_nativeType(type)));
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<bool> setVolume(AudioDeviceType type, double volume) async {
    if (!await _ensureAudio()) return false;
    try {
      return await native.Audio.setVolume(AudioSystemService.normalizeVolume(volume), _nativeType(type)) == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> getMute(AudioDeviceType type) async {
    if (!await _ensureAudio()) return false;
    try {
      return await native.Audio.getMuteAudioDevice(_nativeType(type));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setMute(AudioDeviceType type, bool muted) async {
    if (!await _ensureAudio()) return false;
    try {
      return await native.Audio.setMuteAudioDevice(muted, _nativeType(type)) == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    required AudioDeviceTargeting targeting,
  }) async {
    if (!await _ensureAudio() || deviceId.isEmpty) return false;
    try {
      final int result = await native.Audio.setDefaultDevice(
        deviceId,
        console: targeting.console,
        multimedia: targeting.multimedia,
        communications: targeting.communications,
      );
      return result == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> switchDefaultDevice(
    AudioDeviceType type, {
    required AudioDeviceTargeting targeting,
  }) async {
    if (!await _ensureAudio()) return false;
    try {
      return native.Audio.switchDefaultDevice(
        _nativeType(type),
        console: targeting.console,
        multimedia: targeting.multimedia,
        communications: targeting.communications,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) async {
    if (!await _ensureAudio() || deviceId.isEmpty) return 0.0;
    try {
      return AudioSystemService.normalizeVolume(await native.Audio.getAudioDeviceVolume(deviceId));
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) async {
    if (!await _ensureAudio() || deviceId.isEmpty) return false;
    try {
      return await native.Audio.setAudioDeviceVolume(deviceId, AudioSystemService.normalizeVolume(volume));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PlatformAudioProcess>> listProcesses() async {
    if (!await _ensureAudio()) return const <PlatformAudioProcess>[];
    try {
      final List<native.ProcessVolume> processes = await native.Audio.enumAudioMixer() ?? <native.ProcessVolume>[];
      return processes
          .map(
            (native.ProcessVolume process) => PlatformAudioProcess(
              id: process.processId.toString(),
              processId: process.processId,
              processPath: process.processPath,
              volume: AudioSystemService.normalizeVolume(process.maxVolume),
              peakVolume: AudioSystemService.normalizeVolume(process.peakVolume),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <PlatformAudioProcess>[];
    }
  }

  @override
  Future<bool> setProcessVolume(String processId, double volume) async {
    if (!await _ensureAudio()) return false;
    final int? id = int.tryParse(processId);
    if (id == null) return false;
    try {
      await native.Audio.setAudioMixerVolume(id, AudioSystemService.normalizeVolume(volume));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    if (!Platform.isWindows) return false;
    try {
      WinUtils.runPowerShell(<String>['mmsys.cpl']);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openMixerSettings() async {
    if (!Platform.isWindows) return false;
    try {
      Win32.shellOpen('ms-settings:apps-volume');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PlatformMediaSessionResult> listSessions() async {
    if (!Platform.isWindows)
      return const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);
    try {
      final native.MediaSessionResult result = await native.MediaSessionPlugin.getMediaSessions();
      return PlatformMediaSessionResult(
        currentSessionId: result.currentSessionId,
        sessions: result.sessions
            .map(
              (native.MediaSession session) => PlatformMediaSession(
                id: session.id,
                isCurrent: session.isCurrent,
                title: session.title,
                artist: session.artist,
                albumTitle: session.albumTitle,
                albumArtist: session.albumArtist,
                trackNumber: session.trackNumber,
                playbackStatus: session.playbackStatus,
                canPlay: session.canPlay,
                canPause: session.canPause,
                canSkipNext: session.canSkipNext,
                canSkipPrevious: session.canSkipPrevious,
                artworkBytes: session.thumbnail,
                applicationName: session.id,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      return const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);
    }
  }

  @override
  Future<bool> sendCommand(String sessionId, PlatformMediaCommand command) async {
    if (!Platform.isWindows || sessionId.isEmpty) return false;
    try {
      await native.MediaSessionPlugin.sendCommand(sessionId, command.wireName);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> sendGlobalCommand(PlatformMediaCommand command) async {
    if (!Platform.isWindows) return false;
    final String? key = switch (command) {
      PlatformMediaCommand.playPause => nativeKey('MEDIA_PLAY_PAUSE'),
      PlatformMediaCommand.next => nativeKey('MEDIA_NEXT_TRACK'),
      PlatformMediaCommand.previous => nativeKey('MEDIA_PREV_TRACK'),
      _ => null,
    };
    if (key == null) return false;
    try {
      WinKeys.single(key, KeySentMode.normal);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> sendApplicationCommand(PlatformMediaBinding binding, PlatformMediaCommand command) async {
    if (!Platform.isWindows) return false;
    final String configuredHotkey = binding.hotkeyFor(command);
    if (configuredHotkey.isNotEmpty) {
      try {
        WinKeys.send(configuredHotkey);
        return true;
      } catch (_) {
        return false;
      }
    }
    return sendGlobalCommand(command);
  }

  @override
  Future<bool> isApplicationPlaying(PlatformMediaBinding binding) async {
    final PlatformMediaSessionResult result = await listSessions();
    final String needle = binding.applicationId.toLowerCase();
    return result.sessions.any(
      (PlatformMediaSession session) =>
          session.isPlaying &&
          <String>[session.id, session.applicationName, session.title].any(
            (String value) => value.toLowerCase().contains(needle),
          ),
    );
  }

  @override
  Future<bool> launchApplication(PlatformMediaBinding binding) async {
    if (!Platform.isWindows || binding.applicationPath.isEmpty) return false;
    try {
      WinUtils.open(binding.applicationPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  native.AudioDeviceType _nativeType(AudioDeviceType type) =>
      type == AudioDeviceType.input ? native.AudioDeviceType.input : native.AudioDeviceType.output;

  Future<Uint8List?> _iconBytes(native.AudioDevice device) async {
    if (device.iconPath.isEmpty) return null;
    try {
      return await native.nativeIconToBytes(device.iconPath, iconID: device.iconID);
    } catch (_) {
      return null;
    }
  }

  String? nativeKey(String name) {
    switch (name) {
      case 'MEDIA_PLAY_PAUSE':
        return VK.MEDIA_PLAY_PAUSE;
      case 'MEDIA_NEXT_TRACK':
        return VK.MEDIA_NEXT_TRACK;
      case 'MEDIA_PREV_TRACK':
        return VK.MEDIA_PREV_TRACK;
    }
    return null;
  }
}

/// Separates media capability reporting from the audio endpoint probe while
/// reusing the same native method-channel implementation.
class NativeWindowsMediaBackend extends NativeWindowsAudioBackend implements WindowsMediaBackend {
  @override
  bool get isAvailable => isMediaAvailable;

  @override
  Future<bool> initialize() async {
    await super.initialize();
    return isMediaAvailable;
  }
}
