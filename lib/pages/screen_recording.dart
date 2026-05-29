// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/settings.dart' as settings_model;
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';

Future<void> startScreenRecordingPage() async {
  WidgetsFlutterBinding.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(400, 300),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: 'Tabame Screen Recording',
  );

  await windowManager.setPosition(const Offset(-32000, -32000));
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    RecordingOverlayWindow._hwnd = GetAncestor(GetActiveWindow(), 2);
    await Boxes.registerBoxes(justLoad: true);
    RecordingSettingsStore.load();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
  });

  runApp(const ScreenRecordingApp());
}

class RecordingSettingsStore {
  static String get _path => '${WinUtils.getTabameAppDataFolder(settings: true)}\\screen_recording.json';
  static Map<String, dynamic> _data = <String, dynamic>{};

  static void load() {
    try {
      final File file = File(_path);
      if (file.existsSync()) {
        _data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {
      _data = <String, dynamic>{};
    }
  }

  static void save() {
    try {
      final File file = File(_path);
      file.writeAsStringSync(jsonEncode(_data));
    } catch (_) {}
  }

  static String getString(String key, String fallback) => _data[key] as String? ?? fallback;
  static int getInt(String key, int fallback) => (_data[key] as num?)?.toInt() ?? fallback;
  static bool getBool(String key, bool fallback) => _data[key] as bool? ?? fallback;

  static void setString(String key, String value) {
    _data[key] = value;
    save();
  }

  static void setInt(String key, int value) {
    _data[key] = value;
    save();
  }

  static void setBool(String key, bool value) {
    _data[key] = value;
    save();
  }
}

class RecordingOverlayWindow {
  static int _hwnd = 0;
  static bool _clickThrough = false;

  static int get hwnd {
    if (_hwnd != 0) return _hwnd;
    _hwnd = GetAncestor(GetActiveWindow(), 2);
    return _hwnd;
  }

  static Future<void> setupOverlay() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final int target = hwnd;
    if (target == 0) return;

    final int style = GetWindowLongPtr(target, GWL_STYLE);
    SetWindowLongPtr(
      target,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );

    final int exStyle = GetWindowLongPtr(target, GWL_EXSTYLE);
    SetWindowLongPtr(target, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TOPMOST);
    SetLayeredWindowAttributes(target, 0, 255, LWA_ALPHA);

    final int vLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final int vTop = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final int vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final int vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);

    SetWindowPos(
      target,
      HWND_TOPMOST,
      vLeft,
      vTop,
      vWidth,
      vHeight,
      SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  static Future<void> showHud() async {
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(true);
    await setupOverlay();
    disableClickThrough();
    await windowManager.show();
    await windowManager.focus();
  }

  static void enableClickThrough() {
    if (_clickThrough) return;
    final int target = hwnd;
    if (target == 0) return;
    final int exStyle = GetWindowLongPtr(target, GWL_EXSTYLE);
    SetWindowLongPtr(
      target,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
    );
    SetWindowPos(
      target,
      0,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
    );
    _clickThrough = true;
  }

  static void disableClickThrough() {
    if (!_clickThrough) return;
    final int target = hwnd;
    if (target == 0) return;
    final int exStyle = GetWindowLongPtr(target, GWL_EXSTYLE);
    SetWindowLongPtr(
      target,
      GWL_EXSTYLE,
      exStyle & ~WS_EX_TRANSPARENT & ~WS_EX_NOACTIVATE,
    );
    SetLayeredWindowAttributes(target, 0, 255, LWA_ALPHA);
    SetWindowPos(
      target,
      0,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED,
    );
    _clickThrough = false;
  }

  static void setClickThrough(bool enabled) {
    if (enabled) {
      enableClickThrough();
    } else {
      disableClickThrough();
    }
  }
}

enum RecordingAfterAction {
  ask,
  openFile,
  openFolder,
  copyFilePath,
}

enum RecordingTargetMode {
  region,
  monitor,
  window,
}

/// Which capture backend to use.
enum VideoSource {
  /// Built-in Windows.Graphics.Capture (WGC) — default.
  wgc,

  /// Launch a user-supplied ffmpeg command for recording.
  ffmpeg,
}

class ScreenRecordingApp extends StatelessWidget {
  const ScreenRecordingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Material(
        type: MaterialType.transparency,
        child: ScreenRecordingView(),
      ),
      theme: ThemeData.dark(useMaterial3: true),
    );
  }
}

class ScreenRecordingView extends StatefulWidget {
  const ScreenRecordingView({super.key});

  @override
  State<ScreenRecordingView> createState() => _ScreenRecordingViewState();
}

class _ScreenRecordingViewState extends State<ScreenRecordingView> {
  RecordingTargetMode _targetMode = RecordingTargetMode.region;
  RecordingAfterAction _afterAction = RecordingAfterAction.ask;
  ScreenRecordingAudioMode _audioMode = ScreenRecordingAudioMode.none;
  int _frameRate = 30;
  int _videoBitrateMbps = 12;
  bool _captureCursor = true;
  bool _captureBorder = false;
  String _saveFolder = '';
  String _selectedMicId = '';
  String _selectedSystemAudioId = '';

  // Video source selection
  VideoSource _videoSource = VideoSource.wgc;
  String _ffmpegCommand = '';
  Process? _ffmpegProcess;

  final List<AudioDevice> _inputDevices = <AudioDevice>[];
  final List<AudioDevice> _outputDevices = <AudioDevice>[];
  Offset _virtualOrigin = Offset.zero;
  Rect _currentMonitorRect = Rect.zero;
  Offset? _dragStart;
  Offset? _dragCurrent;
  Rect? _windowHighlight;
  int? _windowHighlightHandle;
  int? _monitorHighlightHandle;
  Rect _activeRecordingRect = Rect.zero;
  Rect _activeHudRect = Rect.zero;
  Timer? _monitorTimer;
  bool _startingRecording = false;
  bool _recording = false;
  String _recordingPath = '';
  DateTime? _recordingStartedAt;
  Timer? _hudTimer;
  Duration _elapsed = Duration.zero;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    File(_ffmpegDebugLogPath).writeAsStringSync('');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await RecordingOverlayWindow.setupOverlay();
      RecordingOverlayWindow.disableClickThrough();
      await _loadAudioDevices();
      await _refreshVirtualBounds();
      _monitorTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (_recording) {
          _syncRecordingInteractivity();
        } else {
          _refreshMonitorAndHover();
        }
      });
    });
  }

  void _loadSettings() {
    final String targetMode = RecordingSettingsStore.getString('targetMode', 'region');
    _targetMode = RecordingTargetMode.values.firstWhere(
      (RecordingTargetMode mode) => mode.name == targetMode,
      orElse: () => RecordingTargetMode.region,
    );
    final String afterAction = RecordingSettingsStore.getString('afterAction', 'ask');
    _afterAction = RecordingAfterAction.values.firstWhere(
      (RecordingAfterAction value) => value.name == afterAction,
      orElse: () => RecordingAfterAction.ask,
    );
    final String audioMode = RecordingSettingsStore.getString('audioMode', 'none');
    _audioMode = ScreenRecordingAudioMode.values.firstWhere(
      (ScreenRecordingAudioMode value) => value.name == audioMode,
      orElse: () => ScreenRecordingAudioMode.none,
    );
    _frameRate = RecordingSettingsStore.getInt('frameRate', 30);
    _videoBitrateMbps = RecordingSettingsStore.getInt('videoBitrateMbps', 12);
    _captureCursor = RecordingSettingsStore.getBool('captureCursor', true);
    _captureBorder = RecordingSettingsStore.getBool('captureBorder', false);
    _saveFolder = RecordingSettingsStore.getString('saveFolder', _defaultRecordingFolder());
    _selectedMicId = RecordingSettingsStore.getString('micDeviceId', '');
    _selectedSystemAudioId = RecordingSettingsStore.getString('systemAudioDeviceId', '');
    final String videoSource = RecordingSettingsStore.getString('videoSource', 'wgc');
    _videoSource = VideoSource.values.firstWhere(
      (VideoSource v) => v.name == videoSource,
      orElse: () => VideoSource.wgc,
    );
    _ffmpegCommand = RecordingSettingsStore.getString('ffmpegCommand', '');
  }

  Future<void> _loadAudioDevices() async {
    try {
      await Audio.detectAudioSupport(AudioDeviceType.input);
      final List<AudioDevice>? inputs = await Audio.enumDevices(AudioDeviceType.input);
      final List<AudioDevice>? outputs = await Audio.enumDevices(AudioDeviceType.output);
      if (!mounted) return;
      setState(() {
        _inputDevices
          ..clear()
          ..addAll(inputs ?? const <AudioDevice>[]);
        _outputDevices
          ..clear()
          ..addAll(outputs ?? const <AudioDevice>[]);
        if (_selectedMicId.isEmpty && _inputDevices.isNotEmpty) {
          _selectedMicId = _inputDevices.first.id;
        }
        if (_selectedSystemAudioId.isEmpty && _outputDevices.isNotEmpty) {
          _selectedSystemAudioId = _outputDevices.first.id;
        }
      });
    } catch (_) {}
  }

  Future<void> _refreshVirtualBounds() async {
    Monitor.fetchMonitors();
    final Offset virtualOrigin = Offset(
      GetSystemMetrics(SM_XVIRTUALSCREEN).toDouble(),
      GetSystemMetrics(SM_YVIRTUALSCREEN).toDouble(),
    );
    if (mounted) {
      setState(() {
        _virtualOrigin = virtualOrigin;
      });
    }
  }

  void _refreshMonitorAndHover() {
    if (!mounted || _recording) return;
    final Pointer<POINT> point = calloc<POINT>();
    try {
      GetCursorPos(point);
      final int monitor = MonitorFromPoint(point.ref, MONITOR_DEFAULTTONEAREST);
      final Square? square = Monitor.monitorSizes[monitor];
      final Rect screenMonitorRect = square == null
          ? Rect.zero
          : Rect.fromLTWH(square.x.toDouble(), square.y.toDouble(), square.width.toDouble(), square.height.toDouble());
      final Rect monitorRect = _screenRectToLocal(screenMonitorRect);
      Rect? highlight = _windowHighlight;
      int? highlightHandle = _windowHighlightHandle;
      if (_targetMode == RecordingTargetMode.window) {
        final ({Rect? rect, int? hwnd}) data = _windowRectAt(point.ref.x, point.ref.y);
        highlight = data.rect;
        highlightHandle = data.hwnd;
      } else if (_targetMode == RecordingTargetMode.monitor) {
        highlight = monitorRect;
        highlightHandle = monitor;
      }

      if (!mounted) return;
      setState(() {
        _currentMonitorRect = monitorRect;
        _windowHighlight = highlight;
        _windowHighlightHandle = _targetMode == RecordingTargetMode.window ? highlightHandle : null;
        _monitorHighlightHandle = _targetMode == RecordingTargetMode.monitor ? highlightHandle : null;
      });
    } finally {
      calloc.free(point);
    }
  }

  ({Rect? rect, int? hwnd}) _windowRectAt(int x, int y) {
    final Pointer<POINT> point = calloc<POINT>();
    final Pointer<RECT> rect = calloc<RECT>();
    final bool wasClickThrough = _recording;
    try {
      RecordingOverlayWindow.enableClickThrough();
      point.ref
        ..x = x
        ..y = y;
      int hwnd = WindowFromPoint(point.ref);
      if (hwnd == 0) return (rect: null, hwnd: null);
      hwnd = GetAncestor(hwnd, GA_ROOT);
      if (hwnd == 0 || hwnd == RecordingOverlayWindow.hwnd || IsWindowVisible(hwnd) == FALSE) {
        return (rect: null, hwnd: null);
      }
      if (GetWindowRect(hwnd, rect) == 0) return (rect: null, hwnd: null);
      final Rect logical = Rect.fromLTRB(
        rect.ref.left.toDouble(),
        rect.ref.top.toDouble(),
        rect.ref.right.toDouble(),
        rect.ref.bottom.toDouble(),
      );
      if (logical.width < 8 || logical.height < 8) return (rect: null, hwnd: null);
      return (rect: _screenRectToLocal(logical), hwnd: hwnd);
    } finally {
      if (!wasClickThrough) {
        RecordingOverlayWindow.disableClickThrough();
      }
      calloc.free(point);
      calloc.free(rect);
    }
  }

  Rect _screenRectToLocal(Rect rect) {
    return Rect.fromLTWH(
      rect.left - _virtualOrigin.dx,
      rect.top - _virtualOrigin.dy,
      rect.width,
      rect.height,
    );
  }

  Rect _localRectToScreen(Rect rect) {
    return Rect.fromLTWH(
      rect.left + _virtualOrigin.dx,
      rect.top + _virtualOrigin.dy,
      rect.width,
      rect.height,
    );
  }

  String _defaultRecordingFolder() {
    final DateTime now = DateTime.now();
    final String month = intl.DateFormat('MMM').format(now);
    return '${WinUtils.getTabameAppDataFolder()}\\fancyshot\\recordings\\${now.year} - $month';
  }

  Future<String> _buildOutputPath() async {
    final Directory dir = Directory(_saveFolder);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      WinUtils.setSortByDateModifiedDesc(dir.path);
    }
    DateTime now = DateTime.now();
    final String ts = intl.DateFormat('d EEEE HH-mm-ss').format(now);
    return '${dir.path}\\$ts.mp4';
  }

  Future<void> _beginRecordingForRegion(Rect regionRect) async {
    if (_startingRecording || _recording) return;
    final Rect normalized = Rect.fromPoints(regionRect.topLeft, regionRect.bottomRight).normalize();
    if (normalized.width < 8 || normalized.height < 8) return;
    final Rect screenRect = _localRectToScreen(normalized);
    await _startRecording(
      ScreenRecordingConfig(
        targetType: ScreenRecordingTargetType.region,
        outputPath: await _buildOutputPath(),
        regionLeft: screenRect.left.round(),
        regionTop: screenRect.top.round(),
        regionWidth: screenRect.width.round(),
        regionHeight: screenRect.height.round(),
        frameRate: _frameRate,
        videoBitrateMbps: _videoBitrateMbps,
        captureCursor: _captureCursor,
        captureBorder: _captureBorder,
        audioMode: _audioMode,
        micDeviceId: _selectedMicId.isEmpty ? null : _selectedMicId,
        systemAudioDeviceId: _selectedSystemAudioId.isEmpty ? null : _selectedSystemAudioId,
      ),
      normalized,
    );
  }

  Future<void> _beginRecordingForWindow(int hwnd, Rect windowRect) async {
    if (_startingRecording || _recording) return;
    await _startRecording(
      ScreenRecordingConfig(
        targetType: ScreenRecordingTargetType.window,
        outputPath: await _buildOutputPath(),
        hWnd: hwnd,
        frameRate: _frameRate,
        videoBitrateMbps: _videoBitrateMbps,
        captureCursor: _captureCursor,
        captureBorder: _captureBorder,
        audioMode: _audioMode,
        micDeviceId: _selectedMicId.isEmpty ? null : _selectedMicId,
        systemAudioDeviceId: _selectedSystemAudioId.isEmpty ? null : _selectedSystemAudioId,
      ),
      windowRect,
    );
  }

  Future<void> _beginRecordingForMonitor(int monitorHandle, Rect monitorRect) async {
    if (_startingRecording || _recording) return;
    await _startRecording(
      ScreenRecordingConfig(
        targetType: ScreenRecordingTargetType.monitor,
        outputPath: await _buildOutputPath(),
        monitorHandle: monitorHandle,
        frameRate: _frameRate,
        videoBitrateMbps: _videoBitrateMbps,
        captureCursor: _captureCursor,
        captureBorder: _captureBorder,
        audioMode: _audioMode,
        micDeviceId: _selectedMicId.isEmpty ? null : _selectedMicId,
        systemAudioDeviceId: _selectedSystemAudioId.isEmpty ? null : _selectedSystemAudioId,
      ),
      monitorRect,
    );
  }

  Future<void> _startRecording(ScreenRecordingConfig config, Rect targetRect) async {
    // If using an external ffmpeg-based source, delegate to the ffmpeg path.
    if (_videoSource == VideoSource.ffmpeg) {
      await _startFfmpegRecording(config, targetRect);
      return;
    }

    setState(() {
      _startingRecording = true;
      _errorText = null;
    });

    try {
      await excludeWindowFromCapture(RecordingOverlayWindow.hwnd);
      final ScreenRecordingStatus status = await startScreenRecording(config);
      if (!mounted) return;
      _recordingPath = status.outputPath;
      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      _hudTimer?.cancel();
      _hudTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (!mounted || !_recording) return;
        final DateTime? started = _recordingStartedAt;
        if (started != null) {
          setState(() {
            _elapsed = DateTime.now().difference(started);
          });
        }
      });
      await RecordingOverlayWindow.showHud();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _activeRecordingRect = targetRect == Rect.zero ? _currentMonitorRect : targetRect;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncRecordingInteractivity(force: true);
      });
    } on PlatformException catch (error) {
      await includeWindowFromCapture(RecordingOverlayWindow.hwnd);
      RecordingOverlayWindow.disableClickThrough();
      if (!mounted) return;
      setState(() {
        _errorText = error.message ?? error.code;
      });
    } finally {
      if (mounted) {
        setState(() {
          _startingRecording = false;
          _dragStart = null;
          _dragCurrent = null;
          if (!_recording) _activeRecordingRect = Rect.zero;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FFmpeg recording
  // ---------------------------------------------------------------------------

  static String get _ffmpegDebugLogPath => '${WinUtils.getTabameAppDataFolder(settings: true)}\\ffmpeg_debug.log';

  void _ffmpegLog(String message) {
    try {
      final String ts = DateTime.now().toIso8601String();
      final File f = File(_ffmpegDebugLogPath);
      f.writeAsStringSync('[$ts] $message\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Probe ffmpeg dshow for audio capture devices and return the first name
  /// that looks like a loopback / stereo-mix device. Falls back to the first
  /// available audio capture device, or null if none found.
  Future<String?> _probeDshowAudioDevice() async {
    try {
      final ProcessResult result = await Process.run(
        r'ffmpeg.exe',
        <String>['-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'],
        runInShell: false,
      );
      final String output = (result.stderr as String?) ?? '';
      _ffmpegLog('[dshow probe]\n$output');

      final List<String> audioDevices = <String>[];

      // Matches a string inside quotes, followed by "(audio)" later in the line
      final RegExp audioDeviceRegExp = RegExp(r'"([^"]+)"\s*\(audio\)');

      for (final String line in output.split('\n')) {
        final RegExpMatch? match = audioDeviceRegExp.firstMatch(line);
        if (match != null) {
          audioDevices.add(match.group(1)!);
        }
      }

      _ffmpegLog('[dshow probe] Found audio devices: $audioDevices');
      if (audioDevices.isEmpty) return null;
      // LEAVE THIS LIKE THIS, ITS THE ONLY ONE THAT TRULLY WORKS FOR AUDIO
      if (audioDevices.contains("virtual-audio-capturer")) return "virtual-audio-capturer";
      //JUNK CODE:
      // Prefer loopback-style devices by keyword priority.
      const List<String> preferred = <String>[
        'stereo mix',
        'loopback',
        'wave out',
        'what u hear',
        'mixage',
      ];
      for (final String keyword in preferred) {
        final String match = audioDevices.firstWhere(
          (String d) => d.toLowerCase().contains(keyword),
          orElse: () => '',
        );
        if (match.isNotEmpty) return match;
      }
      return audioDevices.first;
    } catch (e) {
      _ffmpegLog('[dshow probe] Exception: $e');
      return null;
    }
  }

  /// Build the default ffmpeg command (gdigrab for video, dshow for audio when enabled).
  /// [audioDevice] is the dshow audio device name resolved before calling this.
  /// Build the default ffmpeg command (gdigrab for video, dshow for audio when enabled).
  /// [audioDevice] is the dshow audio device name resolved before calling this.
  String _buildDefaultFfmpegCommand(String outputPath, {ScreenRecordingConfig? config, String? audioDevice}) {
    final int fps = _frameRate;
    final int br = _videoBitrateMbps;

    // Build gdigrab input flags from config region/monitor if available.
    int x = 0;
    int y = 0;
    int w = 1920; // fallback default width
    int h = 1080; // fallback default height

    if (config != null) {
      if (config.targetType == ScreenRecordingTargetType.region) {
        x = config.regionLeft ?? 0;
        y = config.regionTop ?? 0;
        w = config.regionWidth! & ~1;
        h = config.regionHeight! & ~1;
      } else if (config.targetType == ScreenRecordingTargetType.monitor && config.monitorHandle != null) {
        final int monitor = config.monitorHandle!;
        final Square? sq = Monitor.monitorSizes[monitor];
        if (sq != null) {
          x = sq.x;
          y = sq.y;
          w = sq.width & ~1;
          h = sq.height & ~1;
        }
      }
    }

    final bool withAudio = _audioMode != ScreenRecordingAudioMode.none && audioDevice != null;

    if (withAudio) {
      // ORDER MATTERS: Audio must be the first input stream (-i) to prevent video buffer starvation!
      return 'ffmpeg'
          ' -f dshow -thread_queue_size 1024 -rtbufsize 256M -audio_buffer_size 80 -i audio="$audioDevice"'
          ' -f gdigrab -thread_queue_size 1024 -rtbufsize 256M'
          ' -framerate $fps -offset_x $x -offset_y $y -video_size ${w}x$h -draw_mouse ${_captureCursor ? 1 : 0} -i desktop'
          ' -c:v libx264 -r $fps -preset ultrafast -tune zerolatency'
          ' -b:v ${br}M'
          ' -pix_fmt yuv420p -movflags +faststart'
          ' -c:a aac -ac 2 -b:a 128k'
          ' -y "$outputPath"';
    }

    // Video-only optimization
    return 'ffmpeg'
        ' -f gdigrab -thread_queue_size 1024 -rtbufsize 256M'
        ' -framerate $fps -offset_x $x -offset_y $y -video_size ${w}x$h -draw_mouse ${_captureCursor ? 1 : 0} -i desktop'
        ' -c:v libx264 -r $fps -preset ultrafast -tune zerolatency'
        ' -b:v ${br}M'
        ' -pix_fmt yuv420p -movflags +faststart'
        ' -y "$outputPath"';
  }

  Future<void> _startFfmpegRecording(ScreenRecordingConfig config, Rect targetRect) async {
    setState(() {
      _startingRecording = true;
      _errorText = null;
    });

    try {
      final String outputPath = config.outputPath;
      _recordingPath = outputPath;

      // Probe for a dshow loopback device if audio is requested (only for auto-command).
      String? dshowAudioDevice;
      if (_ffmpegCommand.trim().isEmpty && _audioMode != ScreenRecordingAudioMode.none) {
        dshowAudioDevice = await _probeDshowAudioDevice();
        _ffmpegLog('dshow audio device selected: ${dshowAudioDevice ?? "(none — recording without audio)"}');
      }

      // Build the command.
      String command = _ffmpegCommand.trim();
      if (command.isEmpty) {
        command = _buildDefaultFfmpegCommand(outputPath, config: config, audioDevice: dshowAudioDevice);
      } else if (command.contains('{output}')) {
        command = command.replaceAll('{output}', '"$outputPath"');
      } else {
        command = '$command "$outputPath"';
      }

      _ffmpegLog('--- START ---');
      _ffmpegLog('Output path: $outputPath');
      _ffmpegLog('Target type: ${config.targetType}');
      if (config.targetType == ScreenRecordingTargetType.region) {
        _ffmpegLog(
            'Region: x=${config.regionLeft} y=${config.regionTop} w=${config.regionWidth} h=${config.regionHeight}');
      }
      _ffmpegLog('FPS: ${config.frameRate}  Bitrate: ${config.videoBitrateMbps} Mbps');
      _ffmpegLog('Command: $command');

      final List<String> parts = _splitCommand(command);
      if (parts.isEmpty) {
        _ffmpegLog('ERROR: Command is empty after splitting.');
        setState(() => _errorText = 'FFmpeg command is empty.');
        return;
      }

      _ffmpegLog('Executable: ${parts.first}');
      _ffmpegLog('Args: ${parts.skip(1).toList()}');

      // Do NOT use runInShell — it wraps in cmd.exe which eats stdin.
      _ffmpegProcess = await Process.start(
        parts.first,
        parts.skip(1).toList(),
        runInShell: false,
      );

      _ffmpegLog('Process started. PID: ${_ffmpegProcess!.pid}');

      // Pipe stderr to debug log (ffmpeg writes all output to stderr).
      _ffmpegProcess!.stderr.transform(const SystemEncoding().decoder).listen((String chunk) {
        _ffmpegLog('[stderr] $chunk');
      });
      _ffmpegProcess!.stdout.transform(const SystemEncoding().decoder).listen((String chunk) {
        _ffmpegLog('[stdout] $chunk');
      });

      // Watch for premature exit.
      _ffmpegProcess!.exitCode.then((int code) {
        _ffmpegLog('Process exited with code $code');
        if (mounted && _recording && code != 0) {
          setState(() => _errorText = 'FFmpeg exited (code $code). See ffmpeg_debug.log in settings folder.');
        }
      });

      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
      _hudTimer?.cancel();
      _hudTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (!mounted || !_recording) return;
        final DateTime? started = _recordingStartedAt;
        if (started != null) {
          setState(() => _elapsed = DateTime.now().difference(started));
        }
      });

      await RecordingOverlayWindow.showHud();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _activeRecordingRect = targetRect == Rect.zero ? _currentMonitorRect : targetRect;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncRecordingInteractivity(force: true);
      });
    } catch (e, st) {
      _ffmpegLog('EXCEPTION during start: $e\n$st');
      RecordingOverlayWindow.disableClickThrough();
      if (!mounted) return;
      setState(() => _errorText = 'Failed to start FFmpeg: $e');
    } finally {
      if (mounted) {
        setState(() {
          _startingRecording = false;
          _dragStart = null;
          _dragCurrent = null;
          if (!_recording) _activeRecordingRect = Rect.zero;
        });
      }
    }
  }

  Future<void> _stopFfmpegRecording() async {
    _ffmpegLog('STOP requested.');
    final Process? proc = _ffmpegProcess;
    _ffmpegProcess = null; // clear first so double-tap doesn't re-enter

    if (proc != null) {
      try {
        // Send 'q\n' to ffmpeg stdin — graceful quit that finalises the MP4.
        _ffmpegLog('Writing q to stdin...');
        proc.stdin.write('q\n');
        await proc.stdin.flush();
        _ffmpegLog('Waiting for process exit (10 s timeout)...');
        final int exitCode = await proc.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _ffmpegLog('Timeout — killing process.');
            proc.kill();
            return -1;
          },
        );
        _ffmpegLog('Process exited with code $exitCode after stop.');
      } catch (e) {
        _ffmpegLog('Exception during stop: $e — killing.');
        proc.kill();
      }
    } else {
      _ffmpegLog('STOP called but _ffmpegProcess was already null.');
    }

    _hudTimer?.cancel();
    final String filePath = _recordingPath;
    _ffmpegLog('File path after stop: $filePath');
    _ffmpegLog('File exists: ${File(filePath).existsSync()}');

    await includeWindowFromCapture(RecordingOverlayWindow.hwnd);
    RecordingOverlayWindow.disableClickThrough();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _activeRecordingRect = Rect.zero;
    });
    Navigator.of(context).maybePop();

    if (File(filePath).existsSync()) {
      await _handleAfterAction(filePath);
    } else {
      _ffmpegLog('WARNING: output file not found, skipping after-action.');
    }
  }

  Future<void> _cancelFfmpegRecording() async {
    _ffmpegLog('CANCEL requested.');
    final Process? proc = _ffmpegProcess;
    _ffmpegProcess = null;
    try {
      proc?.kill();
      await proc?.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    } catch (_) {}
    // Delete the partial file.
    try {
      final File f = File(_recordingPath);
      if (f.existsSync()) {
        f.deleteSync();
        _ffmpegLog('Partial file deleted.');
      }
    } catch (_) {}
    _hudTimer?.cancel();
    await includeWindowFromCapture(RecordingOverlayWindow.hwnd);
    RecordingOverlayWindow.disableClickThrough();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = '';
      _activeRecordingRect = Rect.zero;
    });
    Navigator.of(context).maybePop();
  }

  /// Naively split a shell command into tokens (handles double-quoted segments).
  List<String> _splitCommand(String command) {
    final List<String> tokens = <String>[];
    final StringBuffer current = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < command.length; i++) {
      final String ch = command[i];
      if (ch == '"') {
        inQuote = !inQuote;
      } else if (ch == ' ' && !inQuote) {
        if (current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
        }
      } else {
        current.write(ch);
      }
    }
    if (current.isNotEmpty) tokens.add(current.toString());
    return tokens;
  }

  // ---------------------------------------------------------------------------

  Future<void> _stopRecording() async {
    if (_videoSource == VideoSource.ffmpeg) {
      await _stopFfmpegRecording();
      return;
    }
    try {
      final ScreenRecordingStopResult result = await stopScreenRecording();
      await includeWindowFromCapture(RecordingOverlayWindow.hwnd);
      RecordingOverlayWindow.disableClickThrough();
      _hudTimer?.cancel();
      final String filePath = result.filePath;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingPath = filePath;
        _activeRecordingRect = Rect.zero;
      });
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      await _handleAfterAction(filePath);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.message ?? error.code;
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (_videoSource == VideoSource.ffmpeg) {
      await _cancelFfmpegRecording();
      return;
    }
    try {
      await cancelScreenRecording();
      await includeWindowFromCapture(RecordingOverlayWindow.hwnd);
      RecordingOverlayWindow.disableClickThrough();
    } catch (_) {}
    _hudTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = '';
      _activeRecordingRect = Rect.zero;
    });
    Navigator.of(context).maybePop();
  }

  Future<void> _handleAfterAction(String filePath) async {
    switch (_afterAction) {
      case RecordingAfterAction.ask:
      case RecordingAfterAction.openFolder:
        WinUtils.open('explorer.exe', arguments: '/select,"$filePath"', parseParamaters: false);
        break;
      case RecordingAfterAction.openFile:
        await launchWithExplorer(filePath);
        break;
      case RecordingAfterAction.copyFilePath:
        await Clipboard.setData(ClipboardData(text: filePath));
        break;
    }
    windowManager.close();
  }

  String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _openSettings() async {
    const double modalWidth = 460;
    final Rect mon = _currentMonitorRect;
    final double left =
        mon.isEmpty ? 80 : (mon.left + (mon.width - modalWidth) / 2).clamp(mon.left + 8, mon.right - modalWidth - 8);
    final double top = mon.isEmpty ? 80 : (mon.top + 80).clamp(mon.top + 8, mon.bottom - 8);

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setModalState) {
            Future<void> browseFolder() async {
              final String folder = await WinUtils.folderPicker();
              if (folder.isEmpty) return;
              setModalState(() => _saveFolder = folder);
            }

            // Inner dialog content — extracted so the Positioned can size it.
            final Widget dialogContent = Material(
              color: settings_model.userSettings.theme.background,
              borderRadius: BorderRadius.circular(12),
              elevation: 8,
              child: SizedBox(
                width: modalWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'Recording settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (mon.isEmpty ? 600 : mon.height - 200).clamp(200.0, 700.0).toDouble(),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            DropdownButtonFormField<RecordingTargetMode>(
                              initialValue: _targetMode,
                              decoration: const InputDecoration(labelText: 'Target'),
                              items: RecordingTargetMode.values
                                  .map((RecordingTargetMode value) => DropdownMenuItem<RecordingTargetMode>(
                                        value: value,
                                        child: Text(value.name),
                                      ))
                                  .toList(),
                              onChanged: (RecordingTargetMode? value) {
                                if (value == null) return;
                                setModalState(() => _targetMode = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _frameRate,
                              decoration: const InputDecoration(labelText: 'Frame rate'),
                              items: const <int>[24, 30, 60]
                                  .map((int value) => DropdownMenuItem<int>(value: value, child: Text('$value FPS')))
                                  .toList(),
                              onChanged: (int? value) {
                                if (value == null) return;
                                setModalState(() => _frameRate = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _videoBitrateMbps,
                              decoration: const InputDecoration(labelText: 'Quality'),
                              items: const <MapEntry<int, String>>[
                                MapEntry<int, String>(6, 'Standard (6 Mbps)'),
                                MapEntry<int, String>(12, 'High (12 Mbps)'),
                                MapEntry<int, String>(20, 'Ultra (20 Mbps)'),
                              ]
                                  .map((MapEntry<int, String> value) => DropdownMenuItem<int>(
                                        value: value.key,
                                        child: Text(value.value),
                                      ))
                                  .toList(),
                              onChanged: (int? value) {
                                if (value == null) return;
                                setModalState(() => _videoBitrateMbps = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: _captureCursor,
                              onChanged: (bool value) => setModalState(() => _captureCursor = value),
                              title: const Text('Capture cursor'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            SwitchListTile(
                              value: _captureBorder,
                              onChanged: (bool value) => setModalState(() => _captureBorder = value),
                              title: const Text('Capture border'),
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<ScreenRecordingAudioMode>(
                              initialValue: _audioMode,
                              decoration: const InputDecoration(labelText: 'Audio source'),
                              items: ScreenRecordingAudioMode.values
                                  .map((ScreenRecordingAudioMode value) => DropdownMenuItem<ScreenRecordingAudioMode>(
                                        value: value,
                                        child: Text(value.name),
                                      ))
                                  .toList(),
                              onChanged: (ScreenRecordingAudioMode? value) {
                                if (value == null) return;
                                setModalState(() => _audioMode = value);
                              },
                            ),
                            if (_audioMode == ScreenRecordingAudioMode.mic ||
                                _audioMode == ScreenRecordingAudioMode.systemAndMic) ...<Widget>[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _inputDevices.any((AudioDevice e) => e.id == _selectedMicId)
                                    ? _selectedMicId
                                    : (_inputDevices.isNotEmpty ? _inputDevices.first.id : null),
                                decoration: const InputDecoration(labelText: 'Microphone device'),
                                items: _inputDevices
                                    .map((AudioDevice device) =>
                                        DropdownMenuItem<String>(value: device.id, child: Text(device.name)))
                                    .toList(),
                                onChanged: (String? value) {
                                  if (value == null) return;
                                  setModalState(() => _selectedMicId = value);
                                },
                              ),
                            ],
                            if (_audioMode == ScreenRecordingAudioMode.system ||
                                _audioMode == ScreenRecordingAudioMode.systemAndMic) ...<Widget>[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _outputDevices.any((AudioDevice e) => e.id == _selectedSystemAudioId)
                                    ? _selectedSystemAudioId
                                    : (_outputDevices.isNotEmpty ? _outputDevices.first.id : null),
                                decoration: const InputDecoration(labelText: 'System audio device'),
                                items: _outputDevices
                                    .map((AudioDevice device) =>
                                        DropdownMenuItem<String>(value: device.id, child: Text(device.name)))
                                    .toList(),
                                onChanged: (String? value) {
                                  if (value == null) return;
                                  setModalState(() => _selectedSystemAudioId = value);
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            DropdownButtonFormField<RecordingAfterAction>(
                              initialValue: _afterAction,
                              decoration: const InputDecoration(labelText: 'After recording'),
                              items: RecordingAfterAction.values
                                  .map((RecordingAfterAction value) => DropdownMenuItem<RecordingAfterAction>(
                                        value: value,
                                        child: Text(value.name),
                                      ))
                                  .toList(),
                              onChanged: (RecordingAfterAction? value) {
                                if (value == null) return;
                                setModalState(() => _afterAction = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: _saveFolder,
                              decoration: const InputDecoration(labelText: 'Save location'),
                              onChanged: (String value) => _saveFolder = value,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: browseFolder,
                                icon: const Icon(Icons.folder_open_outlined),
                                label: const Text('Browse'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<VideoSource>(
                              initialValue: _videoSource,
                              decoration: const InputDecoration(
                                labelText: 'Video source',
                                helperText: 'WGC = Windows built-in  |  FFmpeg = custom command',
                                helperMaxLines: 2,
                              ),
                              items: const <DropdownMenuItem<VideoSource>>[
                                DropdownMenuItem<VideoSource>(
                                  value: VideoSource.wgc,
                                  child: Text('Windows Graphics Capture (WGC)'),
                                ),
                                DropdownMenuItem<VideoSource>(
                                  value: VideoSource.ffmpeg,
                                  child: Text('FFmpeg (custom command)'),
                                ),
                              ],
                              onChanged: (VideoSource? value) {
                                if (value == null) return;
                                setModalState(() => _videoSource = value);
                              },
                            ),
                            if (_videoSource == VideoSource.ffmpeg) ...<Widget>[
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: _ffmpegCommand,
                                decoration: const InputDecoration(
                                  labelText: 'FFmpeg command',
                                  helperText: 'Leave blank to auto-generate. Use {output} as output path placeholder, '
                                      'or omit it and the path will be appended automatically.',
                                  helperMaxLines: 4,
                                ),
                                maxLines: 3,
                                onChanged: (String value) => _ffmpegCommand = value,
                              ),
                              if (_ffmpegCommand.trim().isEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'Auto-generated command preview:',
                                        style: TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _buildDefaultFfmpegCommand('<output.mp4>'),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white70,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              RecordingSettingsStore.setString('targetMode', _targetMode.name);
                              RecordingSettingsStore.setString('afterAction', _afterAction.name);
                              RecordingSettingsStore.setString('audioMode', _audioMode.name);
                              RecordingSettingsStore.setInt('frameRate', _frameRate);
                              RecordingSettingsStore.setInt('videoBitrateMbps', _videoBitrateMbps);
                              RecordingSettingsStore.setBool('captureCursor', _captureCursor);
                              RecordingSettingsStore.setBool('captureBorder', _captureBorder);
                              RecordingSettingsStore.setString('saveFolder', _saveFolder);
                              RecordingSettingsStore.setString('micDeviceId', _selectedMicId);
                              RecordingSettingsStore.setString('systemAudioDeviceId', _selectedSystemAudioId);
                              RecordingSettingsStore.setString('videoSource', _videoSource.name);
                              RecordingSettingsStore.setString('ffmpegCommand', _ffmpegCommand);
                              Navigator.of(context).pop();
                              setState(() {});
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            return Stack(
              children: <Widget>[
                Positioned(
                  left: left,
                  top: top,
                  width: modalWidth,
                  child: dialogContent,
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _hudTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recording) {
      final Size screenSize = MediaQuery.of(context).size;
      final Rect hudRect = _hudRectForTarget(_activeRecordingRect, screenSize);
      _activeHudRect = hudRect;
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RecordingActivePainter(
                  highlightRect: _activeRecordingRect,
                  accent: settings_model.userSettings.theme.accentColor,
                ),
              ),
            ),
          ),
          Positioned(
            left: hudRect.left,
            top: hudRect.top,
            width: hudRect.width,
            height: hudRect.height,
            child: _RecordingHud(
              elapsed: _formatDuration(_elapsed),
              audioLabel: _audioMode.name,
              filePath: _recordingPath,
              onStop: _stopRecording,
              onCancel: _cancelRecording,
            ),
          ),
        ],
      );
    }

    _activeHudRect = Rect.zero;

    final Rect highlightRect = _targetMode == RecordingTargetMode.region
        ? (_dragStart != null && _dragCurrent != null
            ? Rect.fromPoints(_dragStart!, _dragCurrent!).normalize()
            : Rect.zero)
        : (_windowHighlight ?? Rect.zero);

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
        }
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              // 1. Intercept right-clicks immediately on pointer down
              onPointerDown: (PointerDownEvent event) {
                if ((event.buttons & 2) != 0) {
                  // Right mouse button bitmask
                  if (_dragStart != null) {
                    // Cancel the in-progress region drag.
                    setState(() {
                      _dragStart = null;
                      _dragCurrent = null;
                    });
                  } else {
                    Future<void>.delayed(const Duration(milliseconds: 200), () {
                      Navigator.of(context).maybePop();
                      windowManager.close();
                    });
                  }
                  return;
                }
              },
              // 2. Continuous check: If right-click is pressed while moving, cancel the drag
              onPointerMove: (PointerMoveEvent event) {
                if ((event.buttons & 2) != 0 && _dragStart != null) {
                  setState(() {
                    _dragStart = null;
                    _dragCurrent = null;
                  });
                  return;
                }

                // Optional: Safely track drag positions if GestureDetector acts up
                if (_dragStart != null && _targetMode == RecordingTargetMode.region) {
                  setState(() => _dragCurrent = event.position);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _targetMode == RecordingTargetMode.region
                    ? (DragStartDetails details) {
                        setState(() {
                          _dragStart = details.globalPosition;
                          _dragCurrent = details.globalPosition;
                        });
                      }
                    : null,
                onPanUpdate: _targetMode == RecordingTargetMode.region
                    ? (DragUpdateDetails details) {
                        // Guard clause to ensure we don't update if a right-click just wiped the values
                        if (_dragStart == null) return;
                        setState(() => _dragCurrent = details.globalPosition);
                      }
                    : null,
                onPanEnd: _targetMode == RecordingTargetMode.region
                    ? (_) {
                        // If right-click reset these to null, recording won't trigger. Perfect.
                        if (_dragStart == null || _dragCurrent == null) return;

                        final Rect localRect = Rect.fromPoints(_dragStart!, _dragCurrent!);

                        // Wipe state before calling the recording function to prevent double-triggers
                        setState(() {
                          _dragStart = null;
                          _dragCurrent = null;
                        });

                        _beginRecordingForRegion(localRect);
                      }
                    : null,
                onTapDown: (TapDownDetails details) {
                  if (_targetMode == RecordingTargetMode.window &&
                      _windowHighlightHandle != null &&
                      _windowHighlight != null) {
                    _beginRecordingForWindow(_windowHighlightHandle!, _windowHighlight!);
                  } else if (_targetMode == RecordingTargetMode.monitor &&
                      _monitorHighlightHandle != null &&
                      _currentMonitorRect != Rect.zero) {
                    _beginRecordingForMonitor(_monitorHighlightHandle!, _currentMonitorRect);
                  }
                },
                child: CustomPaint(
                  painter: _RecordingOverlayPainter(
                    dragStart: _dragStart,
                    dragCurrent: _dragCurrent,
                    highlightRect: highlightRect,
                    monitorRect: _targetMode == RecordingTargetMode.monitor ? _currentMonitorRect : Rect.zero,
                    accent: settings_model.userSettings.theme.accentColor,
                    targetMode: _targetMode,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Positioned(
            left: _settingsChipLeft(MediaQuery.of(context).size.width),
            top: (_currentMonitorRect.top + 16).clamp(16.0, double.infinity),
            child: _SettingsChip(
              label:
                  '${_targetMode.name.toUpperCase()}  |  $_frameRate FPS  |  ${_videoSource == VideoSource.wgc ? '$_videoBitrateMbps Mbps' : _videoSource.name.toUpperCase()}',
              onTap: _openSettings,
            ),
          ),
          if (_startingRecording)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_errorText != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Material(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          Positioned(
            left: (_currentMonitorRect.left + 18).clamp(16.0, double.infinity),
            top: (_currentMonitorRect.top + 16).clamp(16.0, double.infinity),
            child: Material(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  _targetMode == RecordingTargetMode.region
                      ? 'Drag to select a recording region'
                      : _targetMode == RecordingTargetMode.window
                          ? 'Hover a window, then click to record it'
                          : 'Click to record the current monitor',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _settingsChipLeft(double screenWidth) {
    const double chipWidth = 264;
    if (_currentMonitorRect == Rect.zero) {
      return screenWidth - chipWidth - 16;
    }
    final double desired = _currentMonitorRect.right - chipWidth - 16;
    return desired.clamp(_currentMonitorRect.left + 16, screenWidth - chipWidth - 16);
  }

  Rect _hudRectForTarget(Rect target, Size screenSize) {
    const double hudWidth = 260;
    const double hudHeight = 40;
    const double gap = 10;
    if (target == Rect.zero) {
      return Rect.fromLTWH(
        (screenSize.width - hudWidth) / 2,
        24,
        hudWidth,
        hudHeight,
      );
    }
    final double left = (target.center.dx - (hudWidth / 2)).clamp(
      12.0,
      screenSize.width - hudWidth - 12,
    );
    final double belowTop = target.bottom + gap;
    final double aboveTop = target.top - hudHeight - gap;
    double top;
    if (belowTop + hudHeight <= screenSize.height - 12) {
      top = belowTop;
    } else if (aboveTop >= 12) {
      top = aboveTop;
    } else {
      top = (screenSize.height - hudHeight - 12).clamp(12.0, screenSize.height - hudHeight - 12);
    }
    return Rect.fromLTWH(left, top, hudWidth, hudHeight);
  }

  void _syncRecordingInteractivity({bool force = false}) {
    if (!mounted || !_recording || _activeHudRect == Rect.zero) return;
    final Pointer<POINT> point = calloc<POINT>();
    try {
      if (GetCursorPos(point) == 0) return;
      final Offset localCursor = Offset(
        point.ref.x.toDouble() - _virtualOrigin.dx,
        point.ref.y.toDouble() - _virtualOrigin.dy,
      );
      final bool insideHud = _activeHudRect.contains(localCursor);
      RecordingOverlayWindow.setClickThrough(!insideHud);
      if (insideHud && force) {
        windowManager.focus();
      }
    } finally {
      calloc.free(point);
    }
  }
}

class _RecordingHud extends StatelessWidget {
  const _RecordingHud({
    required this.elapsed,
    required this.audioLabel,
    required this.filePath,
    required this.onStop,
    required this.onCancel,
  });

  final String elapsed;
  final String audioLabel;
  final String filePath;
  final Future<void> Function() onStop;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Red recording dot (pulsing feel via small size + vivid colour)
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFFF3B30),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // Elapsed time
            Text(
              elapsed,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            // Audio badge
            if (audioLabel != 'none')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  audioLabel,
                  style: const TextStyle(fontSize: 9, color: Colors.white60),
                ),
              ),
            const SizedBox(width: 10),
            // Stop button
            _HudButton(
              label: 'Stop',
              filled: true,
              onTap: onStop,
            ),
            const SizedBox(width: 6),
            // Cancel button
            _HudButton(
              label: 'Cancel',
              filled: false,
              onTap: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFFF3B30) : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _RecordingActivePainter extends CustomPainter {
  const _RecordingActivePainter({
    required this.highlightRect,
    required this.accent,
  });

  final Rect highlightRect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlightRect == Rect.zero) return;
    final Paint glow = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);
    final Paint border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(highlightRect, glow);
    canvas.drawRect(highlightRect, border);
  }

  @override
  bool shouldRepaint(covariant _RecordingActivePainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect || oldDelegate.accent != accent;
  }
}

class _SettingsChip extends StatelessWidget {
  const _SettingsChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.videocam_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.settings_outlined, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingOverlayPainter extends CustomPainter {
  const _RecordingOverlayPainter({
    required this.dragStart,
    required this.dragCurrent,
    required this.highlightRect,
    required this.monitorRect,
    required this.accent,
    required this.targetMode,
  });

  final Offset? dragStart;
  final Offset? dragCurrent;
  final Rect highlightRect;
  final Rect monitorRect;
  final Color accent;
  final RecordingTargetMode targetMode;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.34);
    Rect focusRect = Rect.zero;
    if (targetMode == RecordingTargetMode.region && dragStart != null && dragCurrent != null) {
      focusRect = Rect.fromPoints(dragStart!, dragCurrent!).normalize();
    } else if (targetMode == RecordingTargetMode.window) {
      focusRect = highlightRect;
    } else if (targetMode == RecordingTargetMode.monitor) {
      focusRect = monitorRect;
    }

    if (focusRect == Rect.zero) {
      canvas.drawRect(Offset.zero & size, dimPaint);
      return;
    }

    final Path dimPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(focusRect);
    canvas.drawPath(dimPath, dimPaint);

    final Paint border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(focusRect, border);

    final String label = '${focusRect.width.round()} x ${focusRect.height.round()}';
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double labelX =
        math.max(8, math.min(size.width - painter.width - 8, focusRect.center.dx - painter.width / 2));
    final double labelY = math.max(8, focusRect.bottom + 8);
    painter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _RecordingOverlayPainter oldDelegate) {
    return oldDelegate.dragStart != dragStart ||
        oldDelegate.dragCurrent != dragCurrent ||
        oldDelegate.highlightRect != highlightRect ||
        oldDelegate.monitorRect != monitorRect ||
        oldDelegate.accent != accent ||
        oldDelegate.targetMode != targetMode;
  }
}

extension on Rect {
  Rect normalize() => Rect.fromLTRB(
        math.min(left, right),
        math.min(top, bottom),
        math.max(left, right),
        math.max(top, bottom),
      );
}
