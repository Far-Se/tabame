import 'dart:io';

import '../audio_system_service.dart';

/// Result returned by the injectable Linux command boundary.
class LinuxAudioCommandResult {
  const LinuxAudioCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// Command boundary for user-session audio and MPRIS tools.
///
/// Keeping process execution injectable makes parsing and capability behavior
/// testable without requiring PulseAudio, PipeWire, or playerctl on CI.
abstract class LinuxAudioCommandRunner {
  Future<LinuxAudioCommandResult> run(String executable, List<String> arguments);
}

class ProcessLinuxAudioCommandRunner implements LinuxAudioCommandRunner {
  const ProcessLinuxAudioCommandRunner();

  @override
  Future<LinuxAudioCommandResult> run(String executable, List<String> arguments) async {
    try {
      final ProcessResult result = await Process.run(
        executable,
        arguments,
        runInShell: false,
      );
      return LinuxAudioCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on Object catch (error) {
      return LinuxAudioCommandResult(exitCode: 127, stderr: '$error');
    }
  }
}

enum _LinuxAudioProvider {
  pactl,
  wpctl,
}

/// Linux default-device, volume, and mute adapter.
///
/// The adapter deliberately uses the user-session audio tools rather than the
/// X11/Wayland platform channel. It therefore does not make display-server
/// policy decisions and remains usable wherever the host audio service is
/// reachable.
class LinuxAudioService extends AudioSystemService {
  LinuxAudioService({
    LinuxAudioCommandRunner? runner,
    bool? platformAvailable,
  })  : runner = runner ?? const ProcessLinuxAudioCommandRunner(),
        platformAvailable = platformAvailable ?? Platform.isLinux;

  static final LinuxAudioService instance = LinuxAudioService();

  final LinuxAudioCommandRunner runner;
  final bool platformAvailable;
  _LinuxAudioProvider? _provider;
  Future<bool>? _probeFuture;
  String _unavailableReason = 'Linux audio has not been probed yet.';

  @override
  bool get isAvailable => _provider != null;

  @override
  String get unavailableReason => isAvailable ? '' : _unavailableReason;

  @override
  Future<bool> initialize() async {
    if (!platformAvailable) {
      _unavailableReason = 'The Linux audio adapter is unavailable on this platform.';
      return false;
    }
    final Future<bool>? inFlight = _probeFuture;
    if (inFlight != null) return inFlight;

    final Future<bool> probe = _probe();
    _probeFuture = probe;
    try {
      final bool available = await probe;
      if (!available && identical(_probeFuture, probe)) _probeFuture = null;
      return available;
    } catch (_) {
      if (identical(_probeFuture, probe)) _probeFuture = null;
      rethrow;
    }
  }

  Future<bool> _probe() async {
    final LinuxAudioCommandResult pactl = await runner.run('pactl', <String>['info']);
    if (pactl.succeeded) {
      _provider = _LinuxAudioProvider.pactl;
      _unavailableReason = '';
      return true;
    }

    final LinuxAudioCommandResult wpctl = await runner.run('wpctl', <String>['status']);
    if (wpctl.succeeded) {
      _provider = _LinuxAudioProvider.wpctl;
      _unavailableReason = '';
      return true;
    }

    _unavailableReason = _bestFailureReason(pactl, wpctl);
    return false;
  }

  String _bestFailureReason(LinuxAudioCommandResult pactl, LinuxAudioCommandResult wpctl) {
    final String detail = <String>[pactl.stderr.trim(), wpctl.stderr.trim()]
        .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
    if (detail.isNotEmpty) return 'No pactl or wpctl audio service is available: $detail';
    return 'No pactl or wpctl audio service is available in the Linux user session.';
  }

  @override
  bool get supportsSystemSettings => false;

  @override
  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async {
    if (!await initialize()) return const <PlatformAudioDevice>[];
    return _provider == _LinuxAudioProvider.pactl ? _listPactlDevices(type) : _listWpctlDevices(type);
  }

  Future<List<PlatformAudioDevice>> _listPactlDevices(AudioDeviceType type) async {
    final String kind = type == AudioDeviceType.output ? 'sinks' : 'sources';
    final LinuxAudioCommandResult result = await runner.run('pactl', <String>['list', 'short', kind]);
    if (!result.succeeded) return const <PlatformAudioDevice>[];
    final String? defaultId = await _pactlDefaultId(type);
    final List<PlatformAudioDevice> devices = <PlatformAudioDevice>[];
    for (final String line in result.stdout.split(RegExp(r'\r?\n'))) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final List<String> fields = trimmed.split(RegExp(r'\s+'));
      if (fields.length < 2 || fields.first.toLowerCase() == 'index') continue;
      final String id = fields[0];
      final String name = fields[1];
      devices.add(
        PlatformAudioDevice(
          id: id,
          name: name,
          isDefault: defaultId != null && (defaultId == id || defaultId == name),
        ),
      );
    }
    return devices;
  }

  Future<String?> _pactlDefaultId(AudioDeviceType type) async {
    final String command = type == AudioDeviceType.output ? 'get-default-sink' : 'get-default-source';
    final LinuxAudioCommandResult direct = await runner.run('pactl', <String>[command]);
    if (direct.succeeded && direct.stdout.trim().isNotEmpty) return direct.stdout.trim().split('\n').first.trim();

    final LinuxAudioCommandResult info = await runner.run('pactl', <String>['info']);
    if (!info.succeeded) return null;
    final String label = type == AudioDeviceType.output ? 'Default Sink:' : 'Default Source:';
    for (final String line in info.stdout.split(RegExp(r'\r?\n'))) {
      if (line.trimLeft().startsWith(label)) return line.substring(line.indexOf(':') + 1).trim();
    }
    return null;
  }

  Future<List<PlatformAudioDevice>> _listWpctlDevices(AudioDeviceType type) async {
    final LinuxAudioCommandResult result = await runner.run('wpctl', <String>['status', '-n']);
    if (!result.succeeded) return const <PlatformAudioDevice>[];
    final bool wantSinks = type == AudioDeviceType.output;
    bool inSinks = false;
    bool inSources = false;
    final List<PlatformAudioDevice> devices = <PlatformAudioDevice>[];
    final RegExp entry = RegExp(r'^\s*(\*)?\s*(\d+)\.\s+(.+?)\s*$');
    for (final String line in result.stdout.split(RegExp(r'\r?\n'))) {
      final String trimmed = line.trim();
      final String lower = trimmed.toLowerCase();
      if (lower.endsWith('sinks:') || lower == 'sinks:') {
        inSinks = true;
        inSources = false;
        continue;
      }
      if (lower.endsWith('sources:') || lower == 'sources:') {
        inSinks = false;
        inSources = true;
        continue;
      }
      if (lower.endsWith('filters:') || lower == 'filters:') {
        inSinks = false;
        inSources = false;
        continue;
      }
      if ((wantSinks && !inSinks) || (!wantSinks && !inSources)) continue;
      final RegExpMatch? match = entry.firstMatch(line);
      if (match == null) continue;
      final String name = (match.group(3) ?? '').replaceFirst(RegExp(r'\s+\[vol:.*\]$'), '').trim();
      devices.add(
        PlatformAudioDevice(
          id: match.group(2)!,
          name: name,
          isDefault: match.group(1) == '*',
        ),
      );
    }
    return devices;
  }

  String _pactlTarget(AudioDeviceType type, {String? deviceId}) {
    if (deviceId != null && deviceId.isNotEmpty) return deviceId;
    return type == AudioDeviceType.output ? '@DEFAULT_SINK@' : '@DEFAULT_SOURCE@';
  }

  String _wpctlTarget(AudioDeviceType type, {String? deviceId}) {
    if (deviceId != null && deviceId.isNotEmpty) return deviceId;
    return type == AudioDeviceType.output ? '@DEFAULT_AUDIO_SINK@' : '@DEFAULT_AUDIO_SOURCE@';
  }

  String _pactlKind(AudioDeviceType type) => type == AudioDeviceType.output ? 'sink' : 'source';

  @override
  Future<double> getVolume(AudioDeviceType type) => getDeviceVolume(type, '');

  @override
  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) async {
    if (!await initialize()) return 0.0;
    final LinuxAudioCommandResult result = _provider == _LinuxAudioProvider.pactl
        ? await runner.run('pactl', <String>['get-${_pactlKind(type)}-volume', _pactlTarget(type, deviceId: deviceId)])
        : await runner.run('wpctl', <String>['get-volume', _wpctlTarget(type, deviceId: deviceId)]);
    if (!result.succeeded) return 0.0;
    return _parseVolume(result.stdout);
  }

  double _parseVolume(String output) {
    final RegExpMatch? percent = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(output);
    if (percent != null) {
      return AudioSystemService.normalizeVolume(double.tryParse(percent.group(1)!)! / 100);
    }
    final RegExpMatch? scalar = RegExp(r'Volume:\s*(0?(?:\.\d+)?|1(?:\.0+)?)', caseSensitive: false).firstMatch(output);
    if (scalar != null) return AudioSystemService.normalizeVolume(double.tryParse(scalar.group(1)!) ?? 0.0);
    return 0.0;
  }

  @override
  Future<bool> setVolume(AudioDeviceType type, double volume) => setDeviceVolume(type, '', volume);

  @override
  Future<bool> setDeviceVolume(AudioDeviceType type, String deviceId, double volume) async {
    if (!await initialize()) return false;
    final int percent = (AudioSystemService.normalizeVolume(volume) * 100).round();
    final LinuxAudioCommandResult result = _provider == _LinuxAudioProvider.pactl
        ? await runner.run(
            'pactl',
            <String>['set-${_pactlKind(type)}-volume', _pactlTarget(type, deviceId: deviceId), '$percent%'],
          )
        : await runner.run(
            'wpctl',
            <String>['set-volume', _wpctlTarget(type, deviceId: deviceId), '$percent%'],
          );
    return result.succeeded;
  }

  @override
  Future<bool> getMute(AudioDeviceType type) async {
    if (!await initialize()) return false;
    final LinuxAudioCommandResult result = _provider == _LinuxAudioProvider.pactl
        ? await runner.run('pactl', <String>['get-${_pactlKind(type)}-mute', _pactlTarget(type)])
        : await runner.run('wpctl', <String>['get-volume', _wpctlTarget(type)]);
    if (!result.succeeded) return false;
    return RegExp(r'\b(?:yes|muted)\b', caseSensitive: false).hasMatch(result.stdout);
  }

  @override
  Future<bool> setMute(AudioDeviceType type, bool muted) async {
    if (!await initialize()) return false;
    final LinuxAudioCommandResult result = _provider == _LinuxAudioProvider.pactl
        ? await runner.run(
            'pactl',
            <String>['set-${_pactlKind(type)}-mute', _pactlTarget(type), muted ? '1' : '0'],
          )
        : await runner.run(
            'wpctl',
            <String>['set-mute', _wpctlTarget(type), muted ? '1' : '0'],
          );
    return result.succeeded;
  }

  @override
  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) async {
    if (!await initialize() || deviceId.isEmpty) return false;
    // Linux has one default endpoint per direction; Windows role targeting has
    // no direct equivalent and is intentionally ignored by this adapter.
    final LinuxAudioCommandResult result = _provider == _LinuxAudioProvider.pactl
        ? await runner.run('pactl', <String>['set-default-${_pactlKind(type)}', deviceId])
        : await runner.run('wpctl', <String>['set-default', deviceId]);
    return result.succeeded;
  }

  @override
  Future<bool> switchDefaultDevice(
    AudioDeviceType type, {
    AudioDeviceTargeting targeting = const AudioDeviceTargeting(),
  }) async {
    final List<PlatformAudioDevice> devices = await listDevices(type);
    if (devices.length < 2) return false;
    final int current = devices.indexWhere((PlatformAudioDevice device) => device.isDefault);
    final int next = (current < 0 ? 0 : current + 1) % devices.length;
    return setDefaultDevice(type, devices[next].id, targeting: targeting);
  }

  @override
  Future<List<PlatformAudioProcess>> listProcesses() async => const <PlatformAudioProcess>[];

  @override
  Future<bool> setProcessVolume(String processId, double volume) async => false;
}

/// Linux MPRIS adapter backed by the optional playerctl command.
class LinuxMediaSessionService extends MediaSessionService {
  LinuxMediaSessionService({
    LinuxAudioCommandRunner? runner,
    bool? platformAvailable,
  })  : runner = runner ?? const ProcessLinuxAudioCommandRunner(),
        platformAvailable = platformAvailable ?? Platform.isLinux;

  static final LinuxMediaSessionService instance = LinuxMediaSessionService();

  final LinuxAudioCommandRunner runner;
  final bool platformAvailable;
  Future<bool>? _probeFuture;
  bool _available = false;
  String _unavailableReason = 'Linux media sessions have not been probed yet.';

  @override
  bool get isAvailable => _available;

  @override
  String get unavailableReason => isAvailable ? '' : _unavailableReason;

  @override
  bool get supportsApplicationControls => isAvailable;

  @override
  Future<bool> initialize() async {
    if (!platformAvailable) {
      _unavailableReason = 'The Linux media-session adapter is unavailable on this platform.';
      return false;
    }
    final Future<bool>? inFlight = _probeFuture;
    if (inFlight != null) return inFlight;

    final Future<bool> probe = _probe();
    _probeFuture = probe;
    try {
      final bool available = await probe;
      if (!available && identical(_probeFuture, probe)) _probeFuture = null;
      return available;
    } catch (_) {
      if (identical(_probeFuture, probe)) _probeFuture = null;
      rethrow;
    }
  }

  Future<bool> _probe() async {
    final LinuxAudioCommandResult result = await runner.run('playerctl', <String>['--list-all']);
    _available = result.succeeded;
    _unavailableReason = _available
        ? ''
        : result.stderr.trim().isNotEmpty
            ? 'playerctl is unavailable: ${result.stderr.trim()}'
            : 'playerctl is unavailable in the Linux user session.';
    return _available;
  }

  @override
  Future<PlatformMediaSessionResult> listSessions() async {
    if (!await initialize()) {
      return const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);
    }
    final LinuxAudioCommandResult players = await runner.run('playerctl', <String>['--list-all']);
    if (!players.succeeded)
      return const PlatformMediaSessionResult(currentSessionId: null, sessions: <PlatformMediaSession>[]);

    final List<String> ids = players.stdout
        .split(RegExp(r'\r?\n'))
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final List<PlatformMediaSession> sessions = <PlatformMediaSession>[];
    for (int index = 0; index < ids.length; index++) {
      final PlatformMediaSession? session = await _readSession(ids[index], isCurrent: index == 0);
      if (session != null) sessions.add(session);
    }
    return PlatformMediaSessionResult(
      currentSessionId: sessions.isEmpty ? null : sessions.first.id,
      sessions: sessions,
    );
  }

  Future<PlatformMediaSession?> _readSession(String id, {required bool isCurrent}) async {
    final LinuxAudioCommandResult metadata = await runner.run(
      'playerctl',
      <String>[
        '--player=$id',
        'metadata',
        '--format',
        '{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{mpris:artUrl}}',
      ],
    );
    if (!metadata.succeeded) return null;
    final List<String> fields = metadata.stdout.trimRight().split('\t');
    String field(int index) => index < fields.length ? fields[index].trim() : '';
    final String status = field(0).isEmpty ? 'Unknown' : field(0);
    return PlatformMediaSession(
      id: id,
      isCurrent: isCurrent,
      title: field(1),
      artist: field(2),
      albumTitle: field(3),
      playbackStatus: status,
      canPlay: true,
      canPause: true,
      canSkipNext: true,
      canSkipPrevious: true,
      applicationName: id,
      artworkUrl: field(4),
    );
  }

  @override
  Future<bool> sendCommand(PlatformMediaSession session, PlatformMediaCommand command) async {
    if (!await initialize() || session.id.isEmpty) return false;
    final String? playerctlCommand = _playerctlCommand(command);
    if (playerctlCommand == null) return false;
    final LinuxAudioCommandResult result = await runner.run(
      'playerctl',
      <String>['--player=${session.id}', playerctlCommand],
    );
    return result.succeeded;
  }

  String? _playerctlCommand(PlatformMediaCommand command) => switch (command) {
        PlatformMediaCommand.playPause => 'play-pause',
        PlatformMediaCommand.play => 'play',
        PlatformMediaCommand.pause => 'pause',
        PlatformMediaCommand.next => 'next',
        PlatformMediaCommand.previous => 'previous',
        PlatformMediaCommand.seekForward || PlatformMediaCommand.seekBackward => null,
      };

  @override
  Future<bool> sendGlobalCommand(PlatformMediaCommand command) async {
    final PlatformMediaSession? session = (await listSessions()).currentSession;
    return session == null ? false : sendCommand(session, command);
  }

  @override
  Future<bool> sendApplicationCommand(PlatformMediaBinding binding, PlatformMediaCommand command) async {
    final String needle = binding.applicationId.toLowerCase();
    final PlatformMediaSessionResult result = await listSessions();
    final PlatformMediaSession? session = result.sessions.where((PlatformMediaSession candidate) {
      return <String>[candidate.id, candidate.applicationName, candidate.title]
          .any((String value) => value.toLowerCase().contains(needle));
    }).firstOrNull;
    return session == null ? false : sendCommand(session, command);
  }

  @override
  Future<bool> isApplicationPlaying(PlatformMediaBinding binding) async {
    final String needle = binding.applicationId.toLowerCase();
    final PlatformMediaSessionResult result = await listSessions();
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
    if (!await initialize() || binding.applicationPath.trim().isEmpty) return false;
    final LinuxAudioCommandResult result = await runner.run('xdg-open', <String>[binding.applicationPath]);
    return result.succeeded;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
