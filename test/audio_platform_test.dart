import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/audio_system_service.dart';
import 'package:tabame/platform/linux/linux_audio_service.dart';
import 'package:tabame/platform/windows/windows_audio_service.dart';

void main() {
  test('shared audio orchestration returns normalized endpoint state', () async {
    final _FakeAudioService service = _FakeAudioService();
    final AudioEndpointSnapshot snapshot =
        await AudioOrchestrator(service: service).readEndpoint(AudioDeviceType.output);

    expect(snapshot.devices, hasLength(2));
    expect(snapshot.defaultDevice?.id, 'speakers');
    expect(snapshot.volume, 0.5);
    expect(snapshot.isMuted, isFalse);
    expect(snapshot.deviceVolumes['speakers'], 0.5);

    expect(await AudioOrchestrator(service: service).toggleMute(AudioDeviceType.output), isTrue);
    expect(service.muted, isTrue);
    expect(await AudioOrchestrator(service: service).setVolume(AudioDeviceType.output, 2), isTrue);
    expect(service.lastVolume, 1.0);
  });

  test('Windows adapter delegates neutral operations to its compatibility backend', () async {
    final _FakeWindowsAudioBackend backend = _FakeWindowsAudioBackend();
    final WindowsAudioService service = WindowsAudioService(backend: backend);

    expect(await service.initialize(), isTrue);
    expect(backend.initialized, isTrue);
    expect((await service.listDevices(AudioDeviceType.output)).single.id, 'windows-device');
    expect(await service.setVolume(AudioDeviceType.output, 2), isTrue);
    expect(backend.lastVolume, 1.0);
    expect(
      await service.setDefaultDevice(
        AudioDeviceType.output,
        'windows-device',
        targeting: const AudioDeviceTargeting(console: true, multimedia: false, communications: true),
      ),
      isTrue,
    );
    expect(backend.lastTargeting?.console, isTrue);
    expect(backend.lastTargeting?.multimedia, isFalse);
  });

  test('Linux selects pactl and parses opaque device/default data', () async {
    final _FakeLinuxRunner runner = _FakeLinuxRunner(<String, LinuxAudioCommandResult>{
      'pactl info': const LinuxAudioCommandResult(exitCode: 0),
      'pactl get-default-sink': const LinuxAudioCommandResult(stdout: 'alsa_output.usb\n', exitCode: 0),
      'pactl list short sinks': const LinuxAudioCommandResult(
        exitCode: 0,
        stdout:
            '42\talsa_output.usb\tpipewire\tfloat32le 2ch 48000Hz\tRUNNING\n43\talsa_output.hdmi\tpipewire\tfloat32le 2ch 48000Hz\tIDLE\n',
      ),
      'pactl get-sink-volume @DEFAULT_SINK@': const LinuxAudioCommandResult(
        exitCode: 0,
        stdout: 'Volume: front-left: 50% / 0.50 / -18.06 dB, front-right: 50% / 0.50 / -18.06 dB\n',
      ),
      'pactl get-sink-mute @DEFAULT_SINK@': const LinuxAudioCommandResult(exitCode: 0, stdout: 'Mute: no\n'),
      'pactl get-sink-volume 42': const LinuxAudioCommandResult(exitCode: 0, stdout: 'Volume: 25%\n'),
      'pactl set-sink-volume 42 75%': const LinuxAudioCommandResult(exitCode: 0),
      'pactl set-sink-mute @DEFAULT_SINK@ 1': const LinuxAudioCommandResult(exitCode: 0),
      'pactl set-default-sink 43': const LinuxAudioCommandResult(exitCode: 0),
    });
    final LinuxAudioService service = LinuxAudioService(runner: runner, platformAvailable: true);

    expect(await service.initialize(), isTrue);
    final List<PlatformAudioDevice> devices = await service.listDevices(AudioDeviceType.output);
    expect(devices.map((PlatformAudioDevice device) => device.id), <String>['42', '43']);
    expect(devices.first.isDefault, isTrue);
    expect(devices.first.name, 'alsa_output.usb');
    expect((await service.getDefaultDevice(AudioDeviceType.output))?.id, '42');
    expect(await service.getVolume(AudioDeviceType.output), 0.5);
    expect(await service.getMute(AudioDeviceType.output), isFalse);
    expect(await service.getDeviceVolume(AudioDeviceType.output, '42'), 0.25);
    expect(await service.setDeviceVolume(AudioDeviceType.output, '42', 0.75), isTrue);
    expect(await service.setMute(AudioDeviceType.output, true), isTrue);
    expect(await service.switchDefaultDevice(AudioDeviceType.output), isTrue);
    expect(
      runner.calls.any(
        (List<String> call) => listEquals(call, <String>['pactl', 'set-sink-volume', '42', '75%']),
      ),
      isTrue,
    );
  });

  test('Linux falls back to wpctl without consulting display-server state', () async {
    final _FakeLinuxRunner runner = _FakeLinuxRunner(<String, LinuxAudioCommandResult>{
      'pactl info': const LinuxAudioCommandResult(exitCode: 127, stderr: 'missing'),
      'wpctl status': const LinuxAudioCommandResult(exitCode: 0),
      'wpctl status -n': const LinuxAudioCommandResult(
        exitCode: 0,
        stdout:
            'Audio\n  Sinks:\n    * 52. Built-in Speakers [vol: 0.50]\n  Sources:\n      53. Microphone [vol: 0.75]\n',
      ),
      'wpctl get-volume @DEFAULT_AUDIO_SINK@': const LinuxAudioCommandResult(
        exitCode: 0,
        stdout: 'Volume: 0.50\n',
      ),
      'wpctl set-volume @DEFAULT_AUDIO_SINK@ 80%': const LinuxAudioCommandResult(exitCode: 0),
    });
    final LinuxAudioService service = LinuxAudioService(runner: runner, platformAvailable: true);

    expect(await service.initialize(), isTrue);
    expect((await service.listDevices(AudioDeviceType.output)).single.id, '52');
    expect((await service.listDevices(AudioDeviceType.input)).single.id, '53');
    expect(await service.getVolume(AudioDeviceType.output), 0.5);
    expect(await service.setVolume(AudioDeviceType.output, 0.8), isTrue);
    expect(runner.calls, isNot(contains(<String>['pactl', 'list', 'short', 'sinks'])));
  });

  test('Linux audio probing retries after the service appears', () async {
    final _FakeLinuxRunner runner = _FakeLinuxRunner(<String, LinuxAudioCommandResult>{});
    final LinuxAudioService service = LinuxAudioService(runner: runner, platformAvailable: true);

    expect(await service.initialize(), isFalse);
    runner.responses['pactl info'] = const LinuxAudioCommandResult(exitCode: 0);
    expect(await service.initialize(), isTrue);
    expect(service.isAvailable, isTrue);
  });

  test('missing Linux audio tools are an explicit deferred capability', () async {
    final LinuxAudioService service = LinuxAudioService(
      runner: _FakeLinuxRunner(<String, LinuxAudioCommandResult>{}),
      platformAvailable: true,
    );

    expect(await service.initialize(), isFalse);
    expect(service.isAvailable, isFalse);
    expect(service.unavailableReason, contains('pactl or wpctl'));
    expect(await service.listDevices(AudioDeviceType.output), isEmpty);
  });

  test('playerctl maps one MPRIS player to a neutral media session', () async {
    final _FakeLinuxRunner runner = _FakeLinuxRunner(<String, LinuxAudioCommandResult>{
      'playerctl --list-all': const LinuxAudioCommandResult(exitCode: 0, stdout: 'spotify\n'),
      'playerctl --player=spotify metadata --format {{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{mpris:artUrl}}':
          const LinuxAudioCommandResult(
        exitCode: 0,
        stdout: 'Playing\tTrack title\tArtist\tAlbum\thttps://example.test/art.jpg\n',
      ),
      'playerctl --player=spotify next': const LinuxAudioCommandResult(exitCode: 0),
    });
    final LinuxMediaSessionService service = LinuxMediaSessionService(runner: runner, platformAvailable: true);

    expect(await service.initialize(), isTrue);
    final PlatformMediaSessionResult result = await service.listSessions();
    expect(result.currentSession?.id, 'spotify');
    expect(result.currentSession?.title, 'Track title');
    expect(result.currentSession?.artworkUrl, 'https://example.test/art.jpg');
    expect(await service.sendCommand(result.currentSession!, PlatformMediaCommand.next), isTrue);
  });
}

class _FakeAudioService extends AudioSystemService {
  bool muted = false;
  double lastVolume = 0.5;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async => const <PlatformAudioDevice>[
        PlatformAudioDevice(id: 'speakers', name: 'Speakers', isDefault: true),
        PlatformAudioDevice(id: 'headphones', name: 'Headphones'),
      ];

  @override
  Future<PlatformAudioDevice?> getDefaultDevice(AudioDeviceType type) async =>
      const PlatformAudioDevice(id: 'speakers', name: 'Speakers', isDefault: true);

  @override
  Future<double> getVolume(AudioDeviceType type) async => lastVolume;

  @override
  Future<bool> setVolume(AudioDeviceType type, double volume) async {
    lastVolume = volume;
    return true;
  }

  @override
  Future<bool> getMute(AudioDeviceType type) async => muted;

  @override
  Future<bool> setMute(AudioDeviceType type, bool value) async {
    muted = value;
    return true;
  }

  @override
  Future<double> getDeviceVolume(AudioDeviceType type, String deviceId) async => deviceId == 'speakers' ? 0.5 : 0.25;
}

class _FakeWindowsAudioBackend extends WindowsAudioBackend {
  bool initialized = false;
  double lastVolume = 0;
  AudioDeviceTargeting? lastTargeting;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async {
    initialized = true;
    return true;
  }

  @override
  Future<List<PlatformAudioDevice>> listDevices(AudioDeviceType type) async => const <PlatformAudioDevice>[
        PlatformAudioDevice(id: 'windows-device', name: 'Windows Device', isDefault: true),
      ];

  @override
  Future<bool> setVolume(AudioDeviceType type, double volume) async {
    lastVolume = volume;
    return true;
  }

  @override
  Future<bool> setDefaultDevice(
    AudioDeviceType type,
    String deviceId, {
    required AudioDeviceTargeting targeting,
  }) async {
    lastTargeting = targeting;
    return true;
  }
}

class _FakeLinuxRunner implements LinuxAudioCommandRunner {
  _FakeLinuxRunner(this.responses);

  final Map<String, LinuxAudioCommandResult> responses;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<LinuxAudioCommandResult> run(String executable, List<String> arguments) async {
    final List<String> call = <String>[executable, ...arguments];
    calls.add(call);
    return responses[call.join(' ')] ?? const LinuxAudioCommandResult(exitCode: 127, stderr: 'not configured');
  }
}
