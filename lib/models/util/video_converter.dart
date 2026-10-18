import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../services/notification_coordinator.dart';

class VideoConversionPreset {
  const VideoConversionPreset(this.id, this.label, this.encoder, this.extension);

  final String id;
  final String label;
  final String encoder;
  final String extension;

  bool get isAudio => id.startsWith('audio-');
  bool get isGif => id == 'gif';
  bool get isCopy => id == 'mkv-copy';
  bool get isVideo => !isAudio && !isGif && !isCopy;

  String get suffix => isCopy
      ? '_remuxed'
      : isAudio
          ? '_audio'
          : isGif
              ? '_animated'
              : '_compressed';

  static const List<VideoConversionPreset> all = <VideoConversionPreset>[
    VideoConversionPreset('mp4-h264', 'MP4 · H.264', 'libx264', '.mp4'),
    VideoConversionPreset('mov-h264', 'MOV · H.264', 'libx264', '.mov'),
    VideoConversionPreset('mp4-h265', 'MP4 · H.265', 'libx265', '.mp4'),
    VideoConversionPreset('webm-vp9', 'WebM · VP9', 'libvpx-vp9', '.webm'),
    VideoConversionPreset('mp4-h264-nvenc', 'MP4 · H.264 · NVIDIA', 'h264_nvenc', '.mp4'),
    VideoConversionPreset('mp4-h265-nvenc', 'MP4 · H.265 · NVIDIA', 'hevc_nvenc', '.mp4'),
    VideoConversionPreset('mp4-h264-qsv', 'MP4 · H.264 · Intel', 'h264_qsv', '.mp4'),
    VideoConversionPreset('mp4-h265-qsv', 'MP4 · H.265 · Intel', 'hevc_qsv', '.mp4'),
    VideoConversionPreset('mp4-h264-amf', 'MP4 · H.264 · AMD', 'h264_amf', '.mp4'),
    VideoConversionPreset('mp4-h265-amf', 'MP4 · H.265 · AMD', 'hevc_amf', '.mp4'),
    VideoConversionPreset('audio-mp3', 'MP3 · Extract audio', 'libmp3lame', '.mp3'),
    VideoConversionPreset('audio-m4a', 'M4A · Extract audio', 'aac', '.m4a'),
    VideoConversionPreset('gif', 'GIF · Animated image', 'gif', '.gif'),
    VideoConversionPreset('mkv-copy', 'MKV · Remux', '', '.mkv'),
  ];
}

class VideoConversionOptions {
  VideoConversionOptions([Map<String, dynamic>? saved]) {
    for (final MapEntry<String, dynamic> entry in defaults.entries) {
      final dynamic value = saved?[entry.key];
      values[entry.key] = value.runtimeType == entry.value.runtimeType ? value : entry.value;
    }
    for (final MapEntry<String, Map<String, String>> entry in choices.entries) {
      if (!entry.value.containsKey(text(entry.key))) values[entry.key] = defaults[entry.key];
    }
    if (!VideoConversionPreset.all.any((VideoConversionPreset item) => item.id == text('preset'))) {
      values['preset'] = defaults['preset'];
    }
  }

  static const Map<String, dynamic> defaults = <String, dynamic>{
    'input': '',
    'output_dir': '',
    'output_name': '',
    'preset': 'mp4-h264',
    'quality': 'balanced',
    'speed': 'balanced',
    'resolution': 'keep',
    'fps': 'keep',
    'audio_bitrate': '160k',
    'remove_audio': false,
    'overwrite': false,
    'open_when_done': false,
    'trim_enabled': false,
    'trim_start': '',
    'trim_end': '',
    'crop_enabled': false,
    'crop_left': '0',
    'crop_top': '0',
    'crop_right': '0',
    'crop_bottom': '0',
  };

  static const Map<String, Map<String, String>> choices = <String, Map<String, String>>{
    'quality': <String, String>{
      'best': 'Best · largest file',
      'high': 'High quality',
      'balanced': 'Balanced',
      'small': 'Small file',
      'smallest': 'Smallest · lower quality'
    },
    'speed': <String, String>{'slow': 'Slow · better compression', 'balanced': 'Balanced', 'fast': 'Fast'},
    'resolution': <String, String>{
      'keep': 'Original',
      '2160': '2160p · 4K',
      '1440': '1440p',
      '1080': '1080p',
      '720': '720p',
      '480': '480p'
    },
    'fps': <String, String>{'keep': 'Original', '60': '60 fps', '30': '30 fps', '24': '24 fps', '15': '15 fps'},
    'audio_bitrate': <String, String>{
      '320k': '320 kbps',
      '256k': '256 kbps',
      '192k': '192 kbps',
      '160k': '160 kbps',
      '128k': '128 kbps',
      '96k': '96 kbps'
    },
  };

  final Map<String, dynamic> values = <String, dynamic>{};
  String text(String key) => values[key] as String;
  bool flag(String key) => values[key] as bool;
  VideoConversionPreset get preset =>
      VideoConversionPreset.all.firstWhere((VideoConversionPreset item) => item.id == text('preset'));
}

/// Parsed edit values are shared by form validation and FFmpeg command creation.
class VideoConversionEdits {
  const VideoConversionEdits({this.start = 0, this.end, this.crop});

  final double start;
  final double? end;
  final ({int left, int top, int right, int bottom})? crop;

  factory VideoConversionEdits.fromOptions(VideoConversionOptions options) {
    final double start = options.flag('trim_enabled') ? _time(options.text('trim_start'), 'Trim start') ?? 0 : 0;
    final double? end = options.flag('trim_enabled') ? _time(options.text('trim_end'), 'Trim end') : null;
    if (end != null && end <= start) throw const FormatException('Trim end must be after the start.');

    ({int left, int top, int right, int bottom})? crop;
    // Saved crop settings are inactive for audio-only and stream-copy presets.
    if (options.flag('crop_enabled') && (options.preset.isVideo || options.preset.isGif)) {
      int margin(String side) {
        final String raw = options.text('crop_$side').trim();
        final int? value = raw.isEmpty ? 0 : int.tryParse(raw);
        if (value == null || value < 0 || value > 1000000) {
          throw FormatException('Crop $side must be a non-negative whole number of pixels.');
        }
        return value;
      }

      crop = (left: margin('left'), top: margin('top'), right: margin('right'), bottom: margin('bottom'));
    }
    return VideoConversionEdits(start: start, end: end, crop: crop);
  }

  static double? _time(String raw, String label) {
    final String value = raw.trim();
    if (value.isEmpty) return null;
    if (!RegExp(r'^\d+(?::\d{1,2}){0,2}(?:\.\d{1,6})?$').hasMatch(value)) {
      throw FormatException('$label must use seconds, MM:SS, or HH:MM:SS (decimals allowed).');
    }
    final List<String> parts = value.split(':');
    double seconds = 0;
    for (int index = 0; index < parts.length; index++) {
      final double part = double.parse(parts[index]);
      if (index > 0 && part >= 60) throw FormatException('$label has a minutes or seconds component of 60 or more.');
      seconds = seconds * 60 + part;
    }
    if (!seconds.isFinite || seconds > 1000000000) throw FormatException('$label is too large.');
    return seconds;
  }

  double? selectedDuration(double? sourceDuration) {
    if (sourceDuration != null) {
      if (start >= sourceDuration) throw const FormatException('Trim start must be before the end of the media.');
      if (end != null && end! > sourceDuration + 0.05) {
        throw const FormatException('Trim end is beyond the media duration. Leave it empty to use the end.');
      }
    }
    final double? stop = end == null
        ? sourceDuration
        : sourceDuration != null && end! > sourceDuration
            ? sourceDuration
            : end;
    return stop == null ? null : stop - start;
  }

  void validateCrop(Map<String, dynamic> metadata, {required bool evenDimensions}) {
    final ({int left, int top, int right, int bottom})? margins = crop;
    if (margins == null) return;
    Map<dynamic, dynamic>? video;
    for (final dynamic stream in (metadata['streams'] as List<dynamic>? ?? <dynamic>[])) {
      if (stream is Map && stream['codec_type'] == 'video') {
        video = stream;
        break;
      }
    }
    int width = int.tryParse('${video?['width']}') ?? 0;
    int height = int.tryParse('${video?['height']}') ?? 0;
    if (width <= 0 || height <= 0) {
      throw const FormatException(
          'Could not read video dimensions for cropping. Make sure ffprobe is on PATH and the input contains video.');
    }
    // FFmpeg autorotates before applying user filters. Use displayed dimensions
    // for portrait videos, including files with older rotate tags.
    final dynamic tags = video?['tags'];
    double rotation = tags is Map ? double.tryParse('${tags['rotate']}') ?? 0 : 0;
    for (final dynamic sideData in (video?['side_data_list'] as List<dynamic>? ?? <dynamic>[])) {
      if (sideData is Map && sideData['rotation'] != null) {
        rotation = double.tryParse('${sideData['rotation']}') ?? rotation;
        break;
      }
    }
    if ((rotation.abs() % 180 - 90).abs() < 0.01) {
      final int originalWidth = width;
      width = height;
      height = originalWidth;
    }
    final int croppedWidth = width - margins.left - margins.right;
    final int croppedHeight = height - margins.top - margins.bottom;
    if (croppedWidth <= 0 || croppedHeight <= 0) {
      throw FormatException('Crop margins exceed the $width × $height video. Keep some width and height.');
    }
    if (evenDimensions && (croppedWidth.isOdd || croppedHeight.isOdd)) {
      throw FormatException(
          'The crop leaves $croppedWidth × $croppedHeight pixels. Adjust the margins to leave even width and height for video encoding.');
    }
  }
}

enum VideoConversionStatus { idle, preparing, converting, complete, cancelled, failed }

/// App-owned job: dismissing a panel only detaches its listener, so reopening it
/// shows the same progress/result. No Python or launcher plugin host is needed.
/// Completion notifications also belong to the job and work while QuickMenu is
/// hidden or disposed, for as long as the Tabame process remains running.
class VideoConverter extends ChangeNotifier {
  VideoConverter._();
  static final VideoConverter instance = VideoConverter._();

  final Set<String> encoders = <String>{};
  VideoConversionStatus status = VideoConversionStatus.idle;
  bool detecting = false;
  bool available = false;
  String? toolError;
  String? error;
  String diagnostics = '';
  String inputPath = '';
  String? outputPath;
  String presetLabel = '';
  String speed = '—';
  String? probeWarning;
  int sourceBytes = 0;
  int outputBytes = 0;
  double? duration;
  double? progress;
  Duration elapsed = Duration.zero;
  Process? _process;
  Timer? _ticker;
  bool _cancelRequested = false;
  bool _finishing = false;

  bool get busy => status == VideoConversionStatus.preparing || status == VideoConversionStatus.converting;
  bool get canCancel => busy && !_cancelRequested && !_finishing;
  bool get cancelling => _cancelRequested && busy;
  List<VideoConversionPreset> get presets => VideoConversionPreset.all
      .where((VideoConversionPreset item) =>
          item.isCopy || encoders.contains(item.encoder) || (item.id == 'audio-mp3' && encoders.contains('mp3')))
      .toList();

  Future<ProcessResult> _inspect(String executable, List<String> args, Duration timeout) async {
    final Process process = await Process.start(executable, args, runInShell: false);
    final Future<String> stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final Future<String> stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
    final int code = await process.exitCode.timeout(timeout, onTimeout: () {
      process.kill();
      return -1;
    });
    return ProcessResult(process.pid, code, await stdout, await stderr);
  }

  Future<void> detectTools() async {
    if (detecting || busy) return;
    detecting = true;
    available = false;
    toolError = null;
    encoders.clear();
    notifyListeners();
    try {
      if (!Platform.isWindows) {
        //TODO: Implement multiplatform
        throw UnsupportedError('Video conversion is currently available on Windows.');
      }
      final ProcessResult result =
          await _inspect('ffmpeg', <String>['-hide_banner', '-encoders'], const Duration(seconds: 8));
      if (result.exitCode != 0) throw StateError('FFmpeg encoder detection failed. ${result.stderr}');
      for (final String line in result.stdout.toString().split('\n')) {
        final RegExpMatch? match = RegExp(r'^\s*[VAS][A-Z.]{5}\s+(\S+)').firstMatch(line);
        if (match != null) encoders.add(match.group(1)!);
      }
      available = true;
    } catch (exception) {
      toolError = exception is ProcessException
          ? 'FFmpeg was not found. Install FFmpeg, add its bin folder to PATH, then restart Tabame.'
          : exception.toString();
    } finally {
      detecting = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _probe(String path) async {
    try {
      final ProcessResult result = await _inspect(
          'ffprobe',
          <String>[
            '-v',
            'error',
            '-show_entries',
            'format=duration:stream=codec_type,avg_frame_rate,width,height:stream_tags=rotate:stream_side_data=rotation',
            '-of',
            'json',
            path,
          ],
          const Duration(seconds: 20));
      if (result.exitCode != 0) throw StateError(result.stderr.toString());
      return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    } catch (_) {
      probeWarning =
          'ffprobe unavailable or unable to read media. Duration is unknown; frame-rate limits are skipped to avoid increasing the source rate.';
      return <String, dynamic>{};
    }
  }

  double? _frameRate(Map<String, dynamic> metadata) {
    for (final dynamic stream in (metadata['streams'] as List<dynamic>? ?? <dynamic>[])) {
      if (stream is! Map || stream['codec_type'] != 'video') continue;
      final List<String> parts = '${stream['avg_frame_rate']}'.split('/');
      final double? numerator = double.tryParse(parts.first);
      final double denominator = parts.length == 2 ? double.tryParse(parts.last) ?? 0 : 1;
      if (numerator != null && numerator > 0 && denominator > 0) return numerator / denominator;
    }
    return null;
  }

  Future<String> _uniquePath(String path) async {
    for (int index = 0; index < 10000; index++) {
      final String candidate = index == 0
          ? path
          : p.join(p.dirname(path), '${p.basenameWithoutExtension(path)} ($index)${p.extension(path)}');
      if (!await FileSystemEntity.isFile(candidate) &&
          !await FileSystemEntity.isDirectory(candidate) &&
          !await Link(candidate).exists()) return candidate;
    }
    throw StateError('Could not find a free output name.');
  }

  Future<String> _destination(VideoConversionOptions options, File source) async {
    final VideoConversionPreset preset = options.preset;
    final String folder = options.text('output_dir').trim();
    final Directory directory = folder.isEmpty ? source.parent : Directory(folder).absolute;
    await directory.create(recursive: true);
    String name = options.text('output_name').trim();
    if (name.toLowerCase().endsWith(preset.extension)) name = name.substring(0, name.length - preset.extension.length);
    if (name.isEmpty) name = '${p.basenameWithoutExtension(source.path)}${preset.suffix}';
    if (RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        name.endsWith('.') ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', caseSensitive: false).hasMatch(name)) {
      throw const FormatException('Choose a valid Windows output file name.');
    }
    String path = p.join(await directory.resolveSymbolicLinks(), '$name${preset.extension}');
    if (p.equals(path.toLowerCase(), source.path.toLowerCase()) ||
        (await File(path).exists() && await FileSystemEntity.identical(path, source.path))) {
      path = p.join(p.dirname(path), '${name}_output${preset.extension}');
    }
    // Never follow an output symlink when replacing a file.
    if (await Link(path).exists()) throw const FormatException('The output is a link. Choose another output name.');
    return options.flag('overwrite') ? path : _uniquePath(path);
  }

  List<String> _arguments(
      VideoConversionOptions options, VideoConversionEdits edits, String input, String output, double? sourceFps) {
    final VideoConversionPreset preset = options.preset;
    final String id = preset.id;
    final int qualityIndex = VideoConversionOptions.choices['quality']!.keys.toList().indexOf(options.text('quality'));
    final bool hardware = id.endsWith('nvenc') || id.endsWith('qsv') || id.endsWith('amf');
    final List<int> quality = preset.isGif
        ? <int>[256, 192, 128, 96, 64]
        : hardware
            ? <int>[18, 21, 25, 29, 34]
            : id.contains('vp9')
                ? <int>[20, 26, 32, 38, 44]
                : id.contains('h265')
                    ? <int>[20, 24, 28, 32, 36]
                    : <int>[17, 20, 23, 27, 31];
    final String q = '${quality[qualityIndex]}';
    final String speed = options.text('speed');
    final String softwareSpeed = <String, String>{'slow': 'slow', 'balanced': 'medium', 'fast': 'veryfast'}[speed]!;
    final String bitrate = options.text('audio_bitrate');
    final List<String> args = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      '-nostdin',
      '-progress',
      'pipe:1',
      '-nostats',
      '-n',
      if (edits.start > 0) ...<String>['-ss', edits.start.toStringAsFixed(6)],
      // Limit decoding too: GIF palette generation needs the complete selected
      // segment before producing frames, rather than reading the whole source.
      if (edits.end != null) ...<String>['-t', (edits.end! - edits.start).toStringAsFixed(6)],
      '-i',
      input,
      if (edits.end != null) ...<String>['-t', (edits.end! - edits.start).toStringAsFixed(6)],
    ];
    final List<String> filters = <String>[];
    final ({int left, int top, int right, int bottom})? crop = edits.crop;
    if (crop != null) {
      filters.add('crop=iw-${crop.left}-${crop.right}:ih-${crop.top}-${crop.bottom}:${crop.left}:${crop.top}:exact=1');
    }
    if (options.text('resolution') != 'keep') {
      filters.add("scale=-2:'min(ih,${options.text('resolution')})':flags=lanczos");
    }
    final double? targetFps = double.tryParse(options.text('fps')) ?? (preset.isGif ? 15 : null);
    if (targetFps != null && sourceFps != null && sourceFps > targetFps) filters.add('fps=$targetFps');

    if (preset.isCopy) {
      args.addAll(<String>['-map', '0', '-c', 'copy']);
    } else if (preset.isAudio) {
      final String encoder = id == 'audio-mp3' && !encoders.contains('libmp3lame') ? 'mp3' : preset.encoder;
      args.addAll(<String>['-vn', '-map', '0:a:0', '-c:a', encoder, '-b:a', bitrate]);
    } else if (preset.isGif) {
      final String chain = filters.isEmpty ? 'null' : filters.join(',');
      args.addAll(<String>[
        '-filter_complex',
        '[0:v:0]$chain,split[a][b];[a]palettegen=max_colors=$q[pal];[b][pal]paletteuse=dither=sierra2_4a',
        '-an',
        '-loop',
        '0'
      ]);
    } else {
      args.addAll(<String>['-map', '0:v:0', '-map', '0:a:0?', '-c:v', preset.encoder]);
      if (filters.isNotEmpty) args.addAll(<String>['-vf', filters.join(',')]);
      if (id.endsWith('nvenc')) {
        args.addAll(<String>[
          '-preset',
          <String, String>{'slow': 'p7', 'balanced': 'p5', 'fast': 'p3'}[speed]!,
          '-tune',
          'hq',
          '-rc',
          'vbr',
          '-cq',
          q,
          '-b:v',
          '0'
        ]);
      } else if (id.endsWith('qsv')) {
        args.addAll(<String>['-global_quality', q, '-preset', softwareSpeed]);
      } else if (id.endsWith('amf')) {
        args.addAll(<String>[
          '-quality',
          <String, String>{'slow': 'quality', 'balanced': 'balanced', 'fast': 'speed'}[speed]!,
          '-rc',
          'cqp',
          '-qp_i',
          q,
          '-qp_p',
          q
        ]);
      } else if (id == 'webm-vp9') {
        args.addAll(<String>[
          '-crf',
          q,
          '-b:v',
          '0',
          '-cpu-used',
          <String, String>{'slow': '1', 'balanced': '2', 'fast': '4'}[speed]!,
          '-row-mt',
          '1'
        ]);
      } else {
        args.addAll(<String>['-preset', softwareSpeed, '-crf', q]);
      }
      if (id.contains('h265')) args.addAll(<String>['-tag:v', 'hvc1']);
      if (!hardware || id == 'mp4-h264-nvenc') args.addAll(<String>['-pix_fmt', 'yuv420p']);
      if (options.flag('remove_audio')) {
        args.add('-an');
      } else if (id == 'webm-vp9') {
        if (!encoders.contains('libopus') && !encoders.contains('libvorbis')) {
          throw StateError(
              'This FFmpeg build needs libopus or libvorbis for WebM audio. Enable Remove audio to continue.');
        }
        args.addAll(<String>['-c:a', encoders.contains('libopus') ? 'libopus' : 'libvorbis', '-b:a', bitrate]);
      } else {
        args.addAll(<String>['-c:a', 'aac', '-b:a', bitrate]);
      }
    }
    if (<String>['.mp4', '.mov', '.m4a'].contains(preset.extension)) args.addAll(<String>['-movflags', '+faststart']);
    return args..addAll(<String>['-map_metadata', '0', output]);
  }

  Future<void> convert(VideoConversionOptions requested, {void Function(String)? onOpen}) async {
    if (busy || detecting || !available) return;
    final VideoConversionOptions options = VideoConversionOptions(requested.values);
    status = VideoConversionStatus.preparing;
    _cancelRequested = false;
    _finishing = false;
    error = null;
    diagnostics = '';
    probeWarning = null;
    outputPath = null;
    outputBytes = 0;
    sourceBytes = 0;
    progress = null;
    duration = null;
    elapsed = Duration.zero;
    speed = '—';
    inputPath = options.text('input').trim();
    presetLabel = options.preset.label;
    final Stopwatch watch = Stopwatch()..start();
    Directory? stagingDirectory;
    File? stagedOutput;
    bool succeeded = false;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = watch.elapsed;
      notifyListeners();
    });
    notifyListeners();
    try {
      if (!Platform.isWindows) {
        //TODO: Implement multiplatform
        throw UnsupportedError('Video conversion is currently available on Windows.');
      }
      if (inputPath.isEmpty || !await File(inputPath).exists())
        throw const FormatException('Choose an existing input media file.');
      final VideoConversionEdits edits = VideoConversionEdits.fromOptions(options);
      final File source = File(await File(inputPath).resolveSymbolicLinks());
      sourceBytes = await source.length();
      inputPath = source.path;
      final Map<String, dynamic> metadata = await _probe(source.path);
      final dynamic format = metadata['format'];
      final double? seconds = format is Map ? double.tryParse('${format['duration']}') : null;
      final double? sourceDuration = seconds != null && seconds.isFinite && seconds > 0 ? seconds : null;
      duration = edits.selectedDuration(sourceDuration);
      edits.validateCrop(metadata, evenDimensions: options.preset.isVideo);
      if (_cancelRequested) return;
      outputPath = await _destination(options, source);
      // Encode beside the destination and publish only after success. Cancelling
      // or failing must never destroy an existing output, even with overwrite on.
      stagingDirectory = await Directory(p.dirname(outputPath!)).createTemp('.tabame-convert-');
      stagedOutput = File(p.join(stagingDirectory.path, 'output${options.preset.extension}'));
      final List<String> args = _arguments(options, edits, source.path, stagedOutput.path, _frameRate(metadata));
      if (_cancelRequested) return;
      final Process process = await Process.start('ffmpeg', args, runInShell: false);
      _process = process;
      final Future<void> errorsDone =
          process.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach((String chunk) {
        diagnostics += chunk;
        if (diagnostics.length > 8000) diagnostics = diagnostics.substring(diagnostics.length - 8000);
      });
      final Future<void> progressDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((String line) {
        final int separator = line.indexOf('=');
        if (separator < 0) return;
        final String key = line.substring(0, separator);
        final String value = line.substring(separator + 1).trim();
        if (key == 'out_time_us' && duration != null) {
          final int? micros = int.tryParse(value);
          if (micros != null) progress = (micros / 1000000 / duration!).clamp(0.0, 1.0);
        } else if (key == 'speed') {
          speed = value;
        } else if (key == 'total_size') {
          outputBytes = int.tryParse(value) ?? outputBytes;
        } else if (key == 'progress') {
          elapsed = watch.elapsed;
          notifyListeners();
        }
      });
      status = VideoConversionStatus.converting;
      if (_cancelRequested) process.kill();
      notifyListeners();
      final int code = await process.exitCode;
      await Future.wait<void>(<Future<void>>[errorsDone, progressDone]);
      _process = null;
      if (_cancelRequested) return;
      if (code != 0) throw StateError('FFmpeg exited with code $code.');
      if (!await stagedOutput.exists() || await stagedOutput.length() == 0)
        throw StateError('FFmpeg did not produce an output file.');
      if (_cancelRequested) return;
      _finishing = true;
      if (!options.flag('overwrite')) outputPath = await _uniquePath(outputPath!);
      if (await Link(outputPath!).exists() ||
          (await File(outputPath!).exists() && await FileSystemEntity.identical(outputPath!, source.path))) {
        throw StateError('The output now points to the source or a link. Choose another name.');
      }
      outputBytes = await stagedOutput.length();
      await stagedOutput.rename(outputPath!);
      succeeded = true;
      progress = 1;
    } catch (exception) {
      if (!_cancelRequested) error = exception.toString();
    } finally {
      _process?.kill();
      _process = null;
      _ticker?.cancel();
      _ticker = null;
      watch.stop();
      elapsed = watch.elapsed;
      try {
        if (stagedOutput != null && await stagedOutput.exists()) await stagedOutput.delete();
        if (stagingDirectory != null && await stagingDirectory.exists()) await stagingDirectory.delete();
      } catch (exception) {
        diagnostics += '\nCould not remove temporary output: $exception';
      }
      status = succeeded
          ? VideoConversionStatus.complete
          : _cancelRequested
              ? VideoConversionStatus.cancelled
              : VideoConversionStatus.failed;
      _finishing = false;
      notifyListeners();
    }
    if (succeeded) {
      // Capture this job's output: a toast may be clicked after another job has
      // started. Delivery is best-effort and must not delay or fail conversion.
      final String completedPath = outputPath!;
      unawaited(NotificationCoordinator.instance.show(
        title: 'Tabame · Conversion complete',
        body: '${p.basename(completedPath)}\n${formatBytes(outputBytes)} · ${formatDuration(elapsed)}',
        onClick: onOpen == null ? null : () => onOpen(completedPath),
      ));
      if (options.flag('open_when_done')) onOpen?.call(completedPath);
    }
  }

  void cancel() {
    if (!canCancel) return;
    _cancelRequested = true;
    _process?.kill();
    notifyListeners();
  }

  void reset() {
    if (busy) return;
    status = VideoConversionStatus.idle;
    error = null;
    notifyListeners();
  }

  Future<void> deleteOutput() async {
    if (status != VideoConversionStatus.complete || outputPath == null) return;
    await File(outputPath!).delete();
    reset();
  }

  static String formatBytes(int bytes) {
    double value = bytes.toDouble();
    for (final String unit in <String>['B', 'KB', 'MB', 'GB', 'TB']) {
      if (value < 1024 || unit == 'TB') return '${value.toStringAsFixed(unit == 'B' ? 0 : 2)} $unit';
      value /= 1024;
    }
    return '$bytes B';
  }

  static String formatDuration(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
