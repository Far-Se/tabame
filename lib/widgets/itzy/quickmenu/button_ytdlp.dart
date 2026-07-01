import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

// ─────────────────────────────────────────────
//  Prefs / storage keys
// ─────────────────────────────────────────────

const String _kOptions = 'ytdlp.options';
const String _kExePath = 'ytdlp.executablePath';
const String _kFfmpegPath = 'ytdlp.ffmpegPath';
const String _kFolder = 'ytdlp.downloadFolder';
const String _kHistoryFile = 'ytdlp_history.json';

/// Marker prefix emitted via yt-dlp's `--progress-template` so download progress
/// arrives as parseable single lines instead of the default carriage-return UI.
const String _progressPrefix = '__TABAME_DL__';

// ─────────────────────────────────────────────
//  Top-bar launcher
// ─────────────────────────────────────────────

/// QuickMenu button that wraps the `yt-dlp` CLI: single or multi-URL downloads,
/// curated common options (video/audio format, quality, thumbnail/metadata/
/// subtitle embedding, SponsorBlock, playlists, cookies…) plus a raw-arguments
/// passthrough, a live download queue, and a persisted history.
class YtDlpButton extends StatelessWidget {
  const YtDlpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "yt-dlp Downloader",
      icon: const Icon(Icons.download_for_offline_outlined),
      child: () => const YtDlpPanel(),
    );
  }
}

// ─────────────────────────────────────────────
//  Models
// ─────────────────────────────────────────────

enum YtDlpOutputMode { video, audio, custom }

enum YtDlpJobStatus { queued, downloading, done, error, cancelled }

/// All user-tunable download options. Serialized as one JSON blob under
/// [_kOptions] and turned into a yt-dlp argument list by [buildArgs].
class YtDlpOptions {
  YtDlpOptions();

  YtDlpOutputMode outputMode = YtDlpOutputMode.video;

  // Video
  String videoContainer = 'mp4'; // mp4 | mkv | webm
  String videoQuality = 'best'; // best | 2160 | 1440 | 1080 | 720 | 480 | 360

  // Audio
  String audioFormat = 'mp3'; // mp3 | m4a | opus | flac | wav
  String audioQuality = '192K'; // best | 128K | 192K | 256K | 320K

  // Custom format string (-f)
  String customFormat = '';

  // Metadata / extras
  bool embedThumbnail = true;
  bool writeThumbnail = false;
  bool embedMetadata = true;
  bool embedChapters = false;
  bool embedSubs = false;
  bool writeSubs = false;
  bool autoSubs = false;
  String subLangs = 'en.*';
  bool sponsorBlock = false;
  bool playlist = false;

  // Advanced
  String cookiesBrowser = 'none'; // none | chrome | edge | firefox | brave | opera | vivaldi
  bool restrictFilenames = false;
  String rateLimit = ''; // e.g. 5M
  String concurrentFragments = '4';
  String outputTemplate = '%(title)s [%(id)s].%(ext)s';
  String customArgs = '';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'outputMode': outputMode.index,
        'videoContainer': videoContainer,
        'videoQuality': videoQuality,
        'audioFormat': audioFormat,
        'audioQuality': audioQuality,
        'customFormat': customFormat,
        'embedThumbnail': embedThumbnail,
        'writeThumbnail': writeThumbnail,
        'embedMetadata': embedMetadata,
        'embedChapters': embedChapters,
        'embedSubs': embedSubs,
        'writeSubs': writeSubs,
        'autoSubs': autoSubs,
        'subLangs': subLangs,
        'sponsorBlock': sponsorBlock,
        'playlist': playlist,
        'cookiesBrowser': cookiesBrowser,
        'restrictFilenames': restrictFilenames,
        'rateLimit': rateLimit,
        'concurrentFragments': concurrentFragments,
        'outputTemplate': outputTemplate,
        'customArgs': customArgs,
      };

  static YtDlpOptions fromJson(Map<String, dynamic> j) {
    final YtDlpOptions o = YtDlpOptions();
    o.outputMode = YtDlpOutputMode
        .values[(j['outputMode'] as int? ?? 0).clamp(0, YtDlpOutputMode.values.length - 1)];
    o.videoContainer = j['videoContainer'] as String? ?? 'mp4';
    o.videoQuality = j['videoQuality'] as String? ?? 'best';
    o.audioFormat = j['audioFormat'] as String? ?? 'mp3';
    o.audioQuality = j['audioQuality'] as String? ?? '192K';
    o.customFormat = j['customFormat'] as String? ?? '';
    o.embedThumbnail = j['embedThumbnail'] as bool? ?? true;
    o.writeThumbnail = j['writeThumbnail'] as bool? ?? false;
    o.embedMetadata = j['embedMetadata'] as bool? ?? true;
    o.embedChapters = j['embedChapters'] as bool? ?? false;
    o.embedSubs = j['embedSubs'] as bool? ?? false;
    o.writeSubs = j['writeSubs'] as bool? ?? false;
    o.autoSubs = j['autoSubs'] as bool? ?? false;
    o.subLangs = j['subLangs'] as String? ?? 'en.*';
    o.sponsorBlock = j['sponsorBlock'] as bool? ?? false;
    o.playlist = j['playlist'] as bool? ?? false;
    o.cookiesBrowser = j['cookiesBrowser'] as String? ?? 'none';
    o.restrictFilenames = j['restrictFilenames'] as bool? ?? false;
    o.rateLimit = j['rateLimit'] as String? ?? '';
    o.concurrentFragments = j['concurrentFragments'] as String? ?? '4';
    o.outputTemplate = j['outputTemplate'] as String? ?? '%(title)s [%(id)s].%(ext)s';
    o.customArgs = j['customArgs'] as String? ?? '';
    return o;
  }

  /// Builds the full yt-dlp argument list for a single [url].
  List<String> buildArgs({
    required String url,
    required String downloadFolder,
    required String ffmpegPath,
  }) {
    final List<String> args = <String>[];

    if (downloadFolder.trim().isNotEmpty) {
      args.addAll(<String>['-P', downloadFolder.trim()]);
    }
    final String tpl = outputTemplate.trim().isEmpty ? '%(title)s [%(id)s].%(ext)s' : outputTemplate.trim();
    args.addAll(<String>['-o', tpl]);

    switch (outputMode) {
      case YtDlpOutputMode.video:
        final String fmt = videoQuality == 'best'
            ? 'bv*+ba/b'
            : 'bv*[height<=$videoQuality]+ba/b[height<=$videoQuality]';
        args.addAll(<String>['-f', fmt, '--merge-output-format', videoContainer]);
        break;
      case YtDlpOutputMode.audio:
        args.addAll(<String>['-x', '--audio-format', audioFormat]);
        args.addAll(<String>['--audio-quality', audioQuality == 'best' ? '0' : audioQuality]);
        break;
      case YtDlpOutputMode.custom:
        if (customFormat.trim().isNotEmpty) {
          args.addAll(<String>['-f', customFormat.trim()]);
        }
        break;
    }

    if (embedThumbnail) args.add('--embed-thumbnail');
    if (writeThumbnail) args.add('--write-thumbnail');
    if (embedMetadata) args.add('--embed-metadata');
    if (embedChapters) args.add('--embed-chapters');
    if (embedSubs) args.add('--embed-subs');
    if (writeSubs) args.add('--write-subs');
    if (autoSubs) args.add('--write-auto-subs');
    if ((embedSubs || writeSubs || autoSubs) && subLangs.trim().isNotEmpty) {
      args.addAll(<String>['--sub-langs', subLangs.trim()]);
    }
    if (sponsorBlock) args.addAll(<String>['--sponsorblock-remove', 'all']);
    args.add(playlist ? '--yes-playlist' : '--no-playlist');

    if (cookiesBrowser != 'none' && cookiesBrowser.trim().isNotEmpty) {
      args.addAll(<String>['--cookies-from-browser', cookiesBrowser]);
    }
    if (restrictFilenames) args.add('--restrict-filenames');
    if (rateLimit.trim().isNotEmpty) args.addAll(<String>['--limit-rate', rateLimit.trim()]);
    final int frags = int.tryParse(concurrentFragments.trim()) ?? 0;
    if (frags > 1) args.addAll(<String>['-N', '$frags']);

    if (ffmpegPath.trim().isNotEmpty) {
      args.addAll(<String>['--ffmpeg-location', ffmpegPath.trim()]);
    }

    // Raw passthrough — anything the curated controls don't cover.
    args.addAll(_tokenizeArgs(customArgs));

    // Progress + robustness (kept just before the URL).
    args.addAll(<String>[
      '--newline',
      '--no-abort-on-error',
      '--progress-template',
      'download:$_progressPrefix %(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
    ]);

    args.add(url);
    return args;
  }
}

/// A single queued/active/finished download.
class YtDlpJob {
  YtDlpJob({required this.url});

  final String url;
  String title = '';
  String statusNote = '';
  YtDlpJobStatus status = YtDlpJobStatus.queued;
  double percent = 0;
  String speedText = '';
  String etaText = '';
  String errorText = '';
  Process? process;

  String get displayTitle => title.isEmpty ? url : title;
}

// ─────────────────────────────────────────────
//  Service — thin wrapper around the yt-dlp executable
// ─────────────────────────────────────────────

class _YtDlpService {
  static String get exe {
    final String custom = (Boxes.pref.getString(_kExePath) ?? '').trim();
    return custom.isEmpty ? 'yt-dlp' : custom;
  }

  static String get ffmpegPath => (Boxes.pref.getString(_kFfmpegPath) ?? '').trim();

  /// Returns the yt-dlp version string, or null if the executable can't be run.
  static Future<String?> version() async {
    try {
      final ProcessResult r = await Process.run(exe, <String>['--version'], runInShell: false);
      if (r.exitCode == 0) {
        final String out = (r.stdout ?? '').toString().trim();
        return out.isEmpty ? null : out.split('\n').first.trim();
      }
    } catch (_) {}
    return null;
  }

  static Future<ProcessResult> update() => Process.run(exe, <String>['-U'], runInShell: false);
}

/// Splits a raw argument string into tokens, honouring double quotes.
List<String> _tokenizeArgs(String input) {
  final String s = input.trim();
  if (s.isEmpty) return <String>[];
  final List<String> tokens = <String>[];
  final RegExp re = RegExp(r'"([^"]*)"|(\S+)');
  for (final RegExpMatch m in re.allMatches(s)) {
    tokens.add(m.group(1) ?? m.group(2) ?? '');
  }
  return tokens;
}

String _basename(String path) {
  final List<String> parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last.trim();
}

String _defaultDownloadFolder() {
  final String userProfile = Platform.environment['USERPROFILE'] ?? '';
  if (userProfile.isEmpty) return '';
  final String downloads = '$userProfile\\Downloads';
  return Directory(downloads).existsSync() ? downloads : userProfile;
}

// ─────────────────────────────────────────────
//  Panel
// ─────────────────────────────────────────────

enum _YtDlpView { main, settings }

class YtDlpPanel extends StatefulWidget {
  const YtDlpPanel({super.key});

  @override
  State<YtDlpPanel> createState() => _YtDlpPanelState();
}

class _YtDlpPanelState extends State<YtDlpPanel> {
  _YtDlpView _view = _YtDlpView.main;

  YtDlpOptions _options = YtDlpOptions();
  String _downloadFolder = '';
  String? _ytDlpVersion;
  bool _advancedOpen = false;

  final List<YtDlpJob> _jobs = <YtDlpJob>[];
  int _activeJobIndex = -1;
  bool _downloading = false;

  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  // Inline feedback strip
  String? _message;
  bool _messageIsError = false;
  Timer? _messageTimer;
  Timer? _versionDebounce;

  // Controllers
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _subLangsController = TextEditingController();
  final TextEditingController _rateLimitController = TextEditingController();
  final TextEditingController _concurrentController = TextEditingController();
  final TextEditingController _outputTemplateController = TextEditingController();
  final TextEditingController _customFormatController = TextEditingController();
  final TextEditingController _customArgsController = TextEditingController();
  final TextEditingController _exePathController = TextEditingController();
  final TextEditingController _ffmpegPathController = TextEditingController();
  final TextEditingController _folderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOptions();

    _downloadFolder = (Boxes.pref.getString(_kFolder) ?? '').trim();
    if (_downloadFolder.isEmpty) _downloadFolder = _defaultDownloadFolder();
    _folderController.text = _downloadFolder;
    _exePathController.text = Boxes.pref.getString(_kExePath) ?? '';
    _ffmpegPathController.text = Boxes.pref.getString(_kFfmpegPath) ?? '';

    _subLangsController.text = _options.subLangs;
    _rateLimitController.text = _options.rateLimit;
    _concurrentController.text = _options.concurrentFragments;
    _outputTemplateController.text = _options.outputTemplate;
    _customFormatController.text = _options.customFormat;
    _customArgsController.text = _options.customArgs;

    _wireOption(_subLangsController, (String v) => _options.subLangs = v);
    _wireOption(_rateLimitController, (String v) => _options.rateLimit = v);
    _wireOption(_concurrentController, (String v) => _options.concurrentFragments = v);
    _wireOption(_outputTemplateController, (String v) => _options.outputTemplate = v);
    _wireOption(_customFormatController, (String v) => _options.customFormat = v);
    _wireOption(_customArgsController, (String v) => _options.customArgs = v);

    _urlController.addListener(() {
      if (mounted) setState(() {});
    });
    _exePathController.addListener(() {
      Boxes.updateSettings(_kExePath, _exePathController.text.trim());
      _versionDebounce?.cancel();
      _versionDebounce = Timer(const Duration(milliseconds: 600), () => unawaited(_detectVersion()));
    });
    _ffmpegPathController.addListener(() {
      Boxes.updateSettings(_kFfmpegPath, _ffmpegPathController.text.trim());
    });

    unawaited(_detectVersion());
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    // Note: any in-flight yt-dlp process is intentionally left running so the
    // download finishes in the background; history is written from static paths.
    _messageTimer?.cancel();
    _versionDebounce?.cancel();
    _urlController.dispose();
    _subLangsController.dispose();
    _rateLimitController.dispose();
    _concurrentController.dispose();
    _outputTemplateController.dispose();
    _customFormatController.dispose();
    _customArgsController.dispose();
    _exePathController.dispose();
    _ffmpegPathController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────

  void _loadOptions() {
    final String raw = Boxes.pref.getString(_kOptions) ?? '';
    if (raw.trim().isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _options = YtDlpOptions.fromJson(decoded);
      }
    } catch (_) {
      _options = YtDlpOptions();
    }
  }

  void _persistOptions() => Boxes.updateSettings(_kOptions, jsonEncode(_options.toJson()));

  void _mutate(VoidCallback fn) {
    setState(fn);
    _persistOptions();
  }

  void _wireOption(TextEditingController c, void Function(String) apply) {
    c.addListener(() {
      apply(c.text);
      _persistOptions();
    });
  }

  String get _historyPath => '${WinUtils.getTabameAppDataFolder(settings: true)}\\$_kHistoryFile';

  Future<void> _loadHistory() async {
    try {
      final File file = File(_historyPath);
      if (file.existsSync()) {
        final String raw = file.readAsStringSync();
        if (raw.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(raw);
          if (decoded is List) {
            _history = decoded
                .whereType<Map<dynamic, dynamic>>()
                .map((Map<dynamic, dynamic> m) =>
                    m.map((dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v)))
                .toList();
          }
        }
      }
    } catch (_) {
      _history = <Map<String, dynamic>>[];
    }
    if (mounted) setState(() {});
  }

  Future<void> _writeHistory() async {
    try {
      final File file = File(_historyPath);
      if (!file.existsSync()) file.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_history));
    } catch (_) {}
  }

  Future<void> _appendHistory(YtDlpJob job) async {
    if (job.status == YtDlpJobStatus.downloading || job.status == YtDlpJobStatus.queued) return;
    _history.insert(0, <String, dynamic>{
      'url': job.url,
      'title': job.displayTitle,
      'status': job.status.name,
      'time': DateTime.now().millisecondsSinceEpoch,
      'folder': _downloadFolder,
    });
    if (_history.length > 50) _history = _history.sublist(0, 50);
    if (mounted) setState(() {});
    await _writeHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _history = <Map<String, dynamic>>[]);
    await _writeHistory();
  }

  // ── Feedback ────────────────────────────────

  void _flash(String message, {bool error = false}) {
    _messageTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  // ── yt-dlp discovery ────────────────────────

  Future<void> _detectVersion() async {
    final String? v = await _YtDlpService.version();
    if (!mounted) return;
    setState(() => _ytDlpVersion = v);
  }

  Future<void> _updateYtDlp() async {
    _flash('Updating yt-dlp…');
    try {
      final ProcessResult r = await _YtDlpService.update();
      final String out = (r.stdout ?? '').toString().trim();
      final String err = (r.stderr ?? '').toString().trim();
      _flash(r.exitCode == 0 ? (out.isEmpty ? 'yt-dlp is up to date' : out.split('\n').last) : (err.isEmpty ? 'Update failed' : err.split('\n').last),
          error: r.exitCode != 0);
    } catch (_) {
      _flash('Could not run yt-dlp -U. Check the path in Settings.', error: true);
    }
    await _detectVersion();
  }

  // ── Queue execution ─────────────────────────

  List<String> _parseUrls(String raw) {
    return raw
        .split(RegExp(r'[\r\n]+'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _startQueue() async {
    final List<String> urls = _parseUrls(_urlController.text);
    if (urls.isEmpty) {
      _flash('Add at least one URL first', error: true);
      return;
    }
    if (_ytDlpVersion == null) {
      _flash('yt-dlp not found. Check Settings.', error: true);
      return;
    }

    setState(() {
      _jobs
        ..clear()
        ..addAll(urls.map((String u) => YtDlpJob(url: u)));
      _downloading = true;
    });

    for (int i = 0; i < _jobs.length; i++) {
      if (!_downloading) break;
      final YtDlpJob job = _jobs[i];
      if (job.status == YtDlpJobStatus.cancelled) continue;
      if (mounted) setState(() => _activeJobIndex = i);
      await _runJob(job);
    }

    if (mounted) {
      setState(() {
        _downloading = false;
        _activeJobIndex = -1;
      });
    }
  }

  Future<void> _runJob(YtDlpJob job) async {
    final List<String> args = _options.buildArgs(
      url: job.url,
      downloadFolder: _downloadFolder,
      ffmpegPath: _YtDlpService.ffmpegPath,
    );
    final StringBuffer errBuf = StringBuffer();
    try {
      final Process proc = await Process.start(_YtDlpService.exe, args, runInShell: false);
      job.process = proc;
      if (mounted) setState(() => job.status = YtDlpJobStatus.downloading);

      proc.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((String line) => _handleStdoutLine(job, line));
      proc.stderr.transform(const SystemEncoding().decoder).transform(const LineSplitter()).listen((String line) {
        if (line.trim().isNotEmpty) errBuf.writeln(line.trim());
      });

      final int code = await proc.exitCode;
      job.process = null;

      if (job.status != YtDlpJobStatus.cancelled) {
        if (code == 0) {
          job.status = YtDlpJobStatus.done;
          job.percent = 1.0;
        } else {
          job.status = YtDlpJobStatus.error;
          job.errorText = _lastError(errBuf.toString());
        }
      }
    } on ProcessException catch (e) {
      job.status = YtDlpJobStatus.error;
      job.errorText = e.errorCode == 2
          ? 'yt-dlp not found. Set its path in Settings or install it.'
          : e.message;
    } catch (e) {
      job.status = YtDlpJobStatus.error;
      job.errorText = e.toString();
    }
    if (mounted) setState(() {});
    await _appendHistory(job);
  }

  void _handleStdoutLine(YtDlpJob job, String raw) {
    final String line = raw.trim();
    if (line.isEmpty) return;

    if (line.startsWith(_progressPrefix)) {
      final List<String> parts = line.substring(_progressPrefix.length).trim().split('|');
      if (parts.isNotEmpty) {
        final double? pct = double.tryParse(parts[0].replaceAll('%', '').trim());
        if (pct != null) job.percent = (pct / 100).clamp(0.0, 1.0);
      }
      if (parts.length > 1) job.speedText = parts[1].trim() == 'Unknown' ? '' : parts[1].trim();
      if (parts.length > 2) job.etaText = parts[2].trim() == 'Unknown' ? '' : parts[2].trim();
      if (mounted) setState(() {});
      return;
    }

    final RegExpMatch? dest = RegExp(r'Destination:\s*(.+)$').firstMatch(line);
    if (dest != null) {
      job.title = _basename(dest.group(1)!);
    } else if (line.contains('Merging formats into')) {
      final RegExpMatch? m = RegExp(r'Merging formats into "?(.+?)"?$').firstMatch(line);
      if (m != null) job.title = _basename(m.group(1)!);
    } else {
      final RegExpMatch? item = RegExp(r'Downloading (?:item|video) (\d+) of (\d+)').firstMatch(line);
      if (item != null) job.statusNote = 'Item ${item.group(1)} of ${item.group(2)}';
    }
    if (mounted) setState(() {});
  }

  String _lastError(String stderr) {
    final List<String> lines =
        stderr.split('\n').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
    final Iterable<String> errs = lines.where((String l) => l.toUpperCase().startsWith('ERROR'));
    final String pick = errs.isNotEmpty ? errs.last : (lines.isNotEmpty ? lines.last : 'Download failed');
    return pick.length > 300 ? pick.substring(0, 300) : pick;
  }

  Future<void> _killProcess(Process proc) async {
    proc.kill();
    try {
      await Process.run('taskkill', <String>['/T', '/F', '/PID', '${proc.pid}'], runInShell: false);
    } catch (_) {}
  }

  Future<void> _cancelJob(YtDlpJob job) async {
    job.status = YtDlpJobStatus.cancelled;
    final Process? p = job.process;
    if (p != null) await _killProcess(p);
    if (mounted) setState(() {});
  }

  Future<void> _cancelAll() async {
    _downloading = false;
    for (final YtDlpJob job in _jobs) {
      if (job.status == YtDlpJobStatus.done || job.status == YtDlpJobStatus.error) continue;
      job.status = YtDlpJobStatus.cancelled;
      final Process? p = job.process;
      if (p != null) await _killProcess(p);
    }
    if (mounted) setState(() {});
  }

  // ── Pickers ─────────────────────────────────

  Future<void> _pasteUrls() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = (data?.text ?? '').trim();
    if (text.isEmpty) return;
    final String existing = _urlController.text.trimRight();
    _urlController.text = existing.isEmpty ? text : '$existing\n$text';
    _urlController.selection = TextSelection.collapsed(offset: _urlController.text.length);
    if (mounted) setState(() {});
  }

  Future<void> _pickFolder() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select download folder';
    if (_downloadFolder.isNotEmpty && Directory(_downloadFolder).existsSync()) {
      picker.initialDirectory = _downloadFolder;
    }
    final Directory? dir = picker.getDirectory();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || dir.path.isEmpty) return;
    setState(() {
      _downloadFolder = dir.path;
      _folderController.text = dir.path;
    });
    Boxes.updateSettings(_kFolder, dir.path);
  }

  Future<void> _pickExe(TextEditingController controller, String key, String title, String filterLabel,
      String filterPattern) async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{filterLabel: filterPattern, 'All files (*.*)': '*.*'}
      ..defaultFilterIndex = 0
      ..title = title;
    final File? file = picker.getFile();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (file == null) return;
    setState(() => controller.text = file.path);
    Boxes.updateSettings(key, file.path);
    if (key == _kExePath) unawaited(_detectVersion());
  }

  void _openFolder(String folder) {
    if (folder.trim().isEmpty) return;
    WinUtils.open(folder, parseParamaters: false);
  }

  // ── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(),
          if (_downloading) const LinearProgressIndicator(minHeight: 1.5),
          if (_message != null) _buildMessageStrip(),
          Flexible(child: _view == _YtDlpView.main ? _buildMainView() : _buildSettingsView()),
          if (_view == _YtDlpView.main) _buildBottomBar(),
        ],
      ),
    );
  }

  PanelHeader _buildHeader() {
    if (_view == _YtDlpView.settings) {
      return PanelHeader(
        title: "yt-dlp Settings",
        icon: Icons.tune_rounded,
        buttonPressed: () => setState(() => _view = _YtDlpView.main),
        buttonIcon: Icons.arrow_back_rounded,
        buttonTooltip: "Back",
      );
    }
    return PanelHeader(
      title: "yt-dlp Downloader",
      icon: Icons.download_for_offline_outlined,
      buttonPressed: () => setState(() => _view = _YtDlpView.settings),
      buttonIcon: Icons.tune_rounded,
      buttonTooltip: "Settings",
    );
  }

  Widget _buildMessageStrip() {
    final Color color = _messageIsError ? Colors.redAccent : Design.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: color.withAlpha(18),
      child: Row(
        children: <Widget>[
          Icon(_messageIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main view ───────────────────────────────

  Widget _buildMainView() {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_ytDlpVersion == null) ...<Widget>[
            _buildMissingBanner(),
            const SizedBox(height: 8),
          ],
          _buildUrlCard(),
          const SizedBox(height: 10),
          _buildSectionLabel(label: "Output", icon: Icons.tune_rounded),
          const SizedBox(height: 8),
          _buildOutputModeRail(),
          const SizedBox(height: 8),
          _buildFormatSection(),
          const SizedBox(height: 12),
          _buildSectionLabel(label: "Extras", icon: Icons.auto_awesome_rounded),
          const SizedBox(height: 8),
          _buildExtrasCard(),
          const SizedBox(height: 10),
          _buildAdvancedCard(),
          const SizedBox(height: 10),
          _buildFolderCard(),
          if (_jobs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _buildSectionLabel(label: "Queue", icon: Icons.playlist_play_rounded, count: _jobs.length),
            const SizedBox(height: 8),
            ..._jobs.asMap().entries.map((MapEntry<int, YtDlpJob> e) => _buildJobRow(e.value, e.key == _activeJobIndex)),
          ],
          if (_history.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _buildHistoryHeader(),
            const SizedBox(height: 8),
            ..._history.take(30).map(_buildHistoryRow),
          ],
        ],
      ),
    );
  }

  Widget _buildMissingBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orangeAccent.withAlpha(60)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orangeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "yt-dlp wasn't found. Open Settings to set its path or install it.",
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(200)),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(icon: Icons.tune_rounded, label: "Settings", onTap: () => setState(() => _view = _YtDlpView.settings)),
        ],
      ),
    );
  }

  Widget _buildUrlCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.link_rounded, size: 14, color: Design.accent),
              const SizedBox(width: 6),
              Text(
                "URLS",
                style: TextStyle(
                    fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Design.text),
              ),
              const Spacer(),
              _SmallButton(icon: Icons.content_paste_rounded, label: "Paste", onTap: _pasteUrls),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Paste one or more links, one per line",
              hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputModeRail() {
    return _segRail(
      items: const <({String value, String label})>[
        (value: 'video', label: 'Video'),
        (value: 'audio', label: 'Audio (mp3)'),
        (value: 'custom', label: 'Custom'),
      ],
      current: _options.outputMode.name,
      onSelect: (String v) => _mutate(() => _options.outputMode = YtDlpOutputMode.values.byName(v)),
    );
  }

  Widget _buildFormatSection() {
    switch (_options.outputMode) {
      case YtDlpOutputMode.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildMiniLabel("Container"),
            const SizedBox(height: 6),
            _segRail(
              items: const <({String value, String label})>[
                (value: 'mp4', label: 'MP4'),
                (value: 'mkv', label: 'MKV'),
                (value: 'webm', label: 'WebM'),
              ],
              current: _options.videoContainer,
              onSelect: (String v) => _mutate(() => _options.videoContainer = v),
            ),
            const SizedBox(height: 10),
            _buildMiniLabel("Max quality"),
            const SizedBox(height: 6),
            _segRail(
              items: const <({String value, String label})>[
                (value: 'best', label: 'Best'),
                (value: '2160', label: '4K'),
                (value: '1440', label: '1440p'),
                (value: '1080', label: '1080p'),
                (value: '720', label: '720p'),
                (value: '480', label: '480p'),
                (value: '360', label: '360p'),
              ],
              current: _options.videoQuality,
              onSelect: (String v) => _mutate(() => _options.videoQuality = v),
            ),
          ],
        );
      case YtDlpOutputMode.audio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildMiniLabel("Format"),
            const SizedBox(height: 6),
            _segRail(
              items: const <({String value, String label})>[
                (value: 'mp3', label: 'MP3'),
                (value: 'm4a', label: 'M4A'),
                (value: 'opus', label: 'Opus'),
                (value: 'flac', label: 'FLAC'),
                (value: 'wav', label: 'WAV'),
              ],
              current: _options.audioFormat,
              onSelect: (String v) => _mutate(() => _options.audioFormat = v),
            ),
            const SizedBox(height: 10),
            _buildMiniLabel("Quality"),
            const SizedBox(height: 6),
            _segRail(
              items: const <({String value, String label})>[
                (value: 'best', label: 'Best'),
                (value: '128K', label: '128k'),
                (value: '192K', label: '192k'),
                (value: '256K', label: '256k'),
                (value: '320K', label: '320k'),
              ],
              current: _options.audioQuality,
              onSelect: (String v) => _mutate(() => _options.audioQuality = v),
            ),
          ],
        );
      case YtDlpOutputMode.custom:
        return _buildFieldCard(
          label: "Format string (-f)",
          hint: 'bestvideo+bestaudio/best',
          controller: _customFormatController,
        );
    }
  }

  Widget _buildExtrasCard() {
    return _card(
      child: Column(
        children: <Widget>[
          _toggleRow(
            icon: Icons.image_rounded,
            label: "Embed thumbnail",
            value: _options.embedThumbnail,
            onChanged: (bool v) => _mutate(() => _options.embedThumbnail = v),
          ),
          _toggleRow(
            icon: Icons.photo_size_select_actual_outlined,
            label: "Save thumbnail file",
            value: _options.writeThumbnail,
            onChanged: (bool v) => _mutate(() => _options.writeThumbnail = v),
          ),
          _toggleRow(
            icon: Icons.sell_outlined,
            label: "Embed metadata",
            value: _options.embedMetadata,
            onChanged: (bool v) => _mutate(() => _options.embedMetadata = v),
          ),
          _toggleRow(
            icon: Icons.list_alt_rounded,
            label: "Embed chapters",
            value: _options.embedChapters,
            onChanged: (bool v) => _mutate(() => _options.embedChapters = v),
          ),
          _toggleRow(
            icon: Icons.closed_caption_off_rounded,
            label: "Embed subtitles",
            value: _options.embedSubs,
            onChanged: (bool v) => _mutate(() => _options.embedSubs = v),
          ),
          _toggleRow(
            icon: Icons.subtitles_outlined,
            label: "Save subtitle files",
            value: _options.writeSubs,
            onChanged: (bool v) => _mutate(() => _options.writeSubs = v),
          ),
          _toggleRow(
            icon: Icons.auto_mode_rounded,
            label: "Auto-generated subs",
            value: _options.autoSubs,
            onChanged: (bool v) => _mutate(() => _options.autoSubs = v),
          ),
          if (_options.embedSubs || _options.writeSubs || _options.autoSubs) ...<Widget>[
            const SizedBox(height: 4),
            _buildInlineField(label: "Sub languages", hint: 'en.*', controller: _subLangsController),
          ],
          _toggleRow(
            icon: Icons.fast_forward_rounded,
            label: "Remove SponsorBlock segments",
            value: _options.sponsorBlock,
            onChanged: (bool v) => _mutate(() => _options.sponsorBlock = v),
          ),
          _toggleRow(
            icon: Icons.playlist_add_check_rounded,
            label: "Download full playlist",
            subtitle: "Off downloads just the linked item",
            value: _options.playlist,
            onChanged: (bool v) => _mutate(() => _options.playlist = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.settings_suggest_outlined, size: 15, color: Design.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Advanced",
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text),
                    ),
                  ),
                  Icon(_advancedOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: Design.text.withAlpha(140)),
                ],
              ),
            ),
          ),
          if (_advancedOpen) ...<Widget>[
            const SizedBox(height: 6),
            _buildMiniLabel("Cookies from browser"),
            const SizedBox(height: 6),
            _segRail(
              items: const <({String value, String label})>[
                (value: 'none', label: 'None'),
                (value: 'chrome', label: 'Chrome'),
                (value: 'edge', label: 'Edge'),
                (value: 'firefox', label: 'Firefox'),
                (value: 'brave', label: 'Brave'),
                (value: 'opera', label: 'Opera'),
                (value: 'vivaldi', label: 'Vivaldi'),
              ],
              current: _options.cookiesBrowser,
              onSelect: (String v) => _mutate(() => _options.cookiesBrowser = v),
            ),
            const SizedBox(height: 8),
            _toggleRow(
              icon: Icons.abc_rounded,
              label: "Restrict filenames",
              subtitle: "ASCII-only, no spaces",
              value: _options.restrictFilenames,
              onChanged: (bool v) => _mutate(() => _options.restrictFilenames = v),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: _buildInlineField(label: "Rate limit", hint: '5M', controller: _rateLimitController)),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildInlineField(
                        label: "Concurrent frags", hint: '4', controller: _concurrentController)),
              ],
            ),
            const SizedBox(height: 6),
            _buildInlineField(label: "Output template", hint: '%(title)s.%(ext)s', controller: _outputTemplateController),
            const SizedBox(height: 6),
            _buildInlineField(
                label: "Custom arguments", hint: '--write-description --sleep-interval 2', controller: _customArgsController),
          ],
        ],
      ),
    );
  }

  Widget _buildFolderCard() {
    return _card(
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_outlined, size: 16, color: Design.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Save to",
                    style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(130))),
                Text(
                  _downloadFolder.isEmpty ? "Not set" : _downloadFolder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(icon: Icons.folder_open_rounded, label: "Change", onTap: _pickFolder),
        ],
      ),
    );
  }

  // ── Queue rows ──────────────────────────────

  Widget _buildJobRow(YtDlpJob job, bool active) {
    final ({Color color, IconData icon}) status = _statusVisual(job.status);
    final String meta = <String>[
      if (job.speedText.isNotEmpty) job.speedText,
      if (job.etaText.isNotEmpty) 'ETA ${job.etaText}',
      if (job.statusNote.isNotEmpty) job.statusNote,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: active ? Design.accent.withAlpha(12) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? Design.accent.withAlpha(50) : Design.text.withAlpha(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(status.icon, size: 14, color: status.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
                  ),
                ),
                if (job.status == YtDlpJobStatus.downloading) ...<Widget>[
                  Text("${(job.percent * 100).toStringAsFixed(0)}%",
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => _cancelJob(job),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.stop_circle_outlined, size: 16, color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
            if (job.status == YtDlpJobStatus.downloading) ...<Widget>[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: job.percent == 0 ? null : job.percent,
                  minHeight: 4,
                  backgroundColor: Design.text.withAlpha(20),
                  valueColor: AlwaysStoppedAnimation<Color>(Design.accent),
                ),
              ),
              if (meta.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(meta, style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(140))),
              ],
            ],
            if (job.status == YtDlpJobStatus.error && job.errorText.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(job.errorText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Colors.redAccent.withAlpha(220))),
            ],
            if (job.status == YtDlpJobStatus.done) ...<Widget>[
              const SizedBox(height: 2),
              InkWell(
                onTap: () => _openFolder(_downloadFolder),
                child: Text("Open folder",
                    style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon}) _statusVisual(YtDlpJobStatus status) {
    switch (status) {
      case YtDlpJobStatus.queued:
        return (color: Design.text.withAlpha(140), icon: Icons.schedule_rounded);
      case YtDlpJobStatus.downloading:
        return (color: Design.accent, icon: Icons.downloading_rounded);
      case YtDlpJobStatus.done:
        return (color: Colors.greenAccent.shade400, icon: Icons.check_circle_rounded);
      case YtDlpJobStatus.error:
        return (color: Colors.redAccent, icon: Icons.error_rounded);
      case YtDlpJobStatus.cancelled:
        return (color: Design.text.withAlpha(120), icon: Icons.cancel_rounded);
    }
  }

  // ── History ─────────────────────────────────

  Widget _buildHistoryHeader() {
    return Row(
      children: <Widget>[
        Icon(Icons.history_rounded, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text("HISTORY",
            style: TextStyle(
                fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Design.text)),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
        const SizedBox(width: 8),
        InkWell(
          onTap: _clearHistory,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text("Clear",
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150), fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> entry) {
    final String statusName = entry['status'] as String? ?? 'done';
    final YtDlpJobStatus status = YtDlpJobStatus.values.firstWhere(
      (YtDlpJobStatus s) => s.name == statusName,
      orElse: () => YtDlpJobStatus.done,
    );
    final ({Color color, IconData icon}) visual = _statusVisual(status);
    final String url = entry['url'] as String? ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      hoverColor: Design.accent.withAlpha(14),
      onTap: () {
        final String existing = _urlController.text.trimRight();
        _urlController.text = existing.isEmpty ? url : '$existing\n$url';
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(visual.icon, size: 13, color: visual.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry['title'] as String? ?? url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(200)),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.north_east_rounded, size: 12, color: Design.text.withAlpha(110)),
          ],
        ),
      ),
    );
  }

  // ── Bottom action bar ───────────────────────

  Widget _buildBottomBar() {
    final bool canDownload = _ytDlpVersion != null && _urlController.text.trim().isNotEmpty && !_downloading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(15)))),
      child: _downloading
          ? _bottomButton(label: "Cancel All", icon: Icons.stop_rounded, color: Colors.redAccent, onTap: _cancelAll)
          : _bottomButton(
              label: "Download",
              icon: Icons.download_rounded,
              color: Design.accent,
              enabled: canDownload,
              onTap: canDownload ? _startQueue : null,
            ),
    );
  }

  Widget _bottomButton({
    required String label,
    required IconData icon,
    required Color color,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(enabled ? 28 : 10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(enabled ? 80 : 30), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 16, color: color.withAlpha(enabled ? 255 : 120)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color.withAlpha(enabled ? 255 : 120),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Settings view ───────────────────────────

  Widget _buildSettingsView() {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildVersionCard(),
          const SizedBox(height: 8),
          _buildSettingCard(
            title: "yt-dlp executable",
            description: "Leave empty to use 'yt-dlp' from PATH.",
            controller: _exePathController,
            hint: "yt-dlp",
            onPick: () => _pickExe(_exePathController, _kExePath, "Select yt-dlp.exe", "yt-dlp.exe", "yt-dlp.exe"),
          ),
          const SizedBox(height: 8),
          _buildSettingCard(
            title: "ffmpeg location",
            description: "Needed for merging & mp3 extraction. Empty uses PATH.",
            controller: _ffmpegPathController,
            hint: "ffmpeg",
            onPick: () => _pickExe(_ffmpegPathController, _kFfmpegPath, "Select ffmpeg.exe", "ffmpeg.exe", "ffmpeg.exe"),
          ),
          const SizedBox(height: 8),
          _buildSettingCard(
            title: "Default download folder",
            description: "Where files are saved.",
            controller: _folderController,
            hint: "%USERPROFILE%\\Downloads",
            onPick: _pickFolder,
            pickIcon: Icons.folder_open_rounded,
            readOnly: true,
          ),
          const SizedBox(height: 12),
          _buildSectionLabel(label: "Maintenance", icon: Icons.build_rounded),
          const SizedBox(height: 8),
          _buildActionRow(
              icon: Icons.system_update_alt_rounded,
              title: "Update yt-dlp",
              subtitle: "yt-dlp -U",
              onTap: _updateYtDlp),
          _buildActionRow(
              icon: Icons.download_rounded,
              title: "Install yt-dlp (winget)",
              subtitle: "winget install yt-dlp.yt-dlp",
              onTap: () => WinUtils.open('cmd',
                  arguments: '/k winget install --id yt-dlp.yt-dlp -e', parseParamaters: false)),
          _buildActionRow(
              icon: Icons.movie_filter_outlined,
              title: "Install ffmpeg (winget)",
              subtitle: "winget install Gyan.FFmpeg",
              onTap: () => WinUtils.open('cmd',
                  arguments: '/k winget install --id Gyan.FFmpeg -e', parseParamaters: false)),
          _buildActionRow(
              icon: Icons.open_in_new_rounded,
              title: "Open yt-dlp releases",
              subtitle: "github.com/yt-dlp/yt-dlp",
              onTap: () => WinUtils.open('https://github.com/yt-dlp/yt-dlp/releases/latest')),
        ],
      ),
    );
  }

  Widget _buildVersionCard() {
    final bool found = _ytDlpVersion != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: found ? Design.accent.withAlpha(10) : Colors.orangeAccent.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: found ? Design.accent.withAlpha(30) : Colors.orangeAccent.withAlpha(50)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: found ? Colors.greenAccent.shade400 : Colors.orangeAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              found ? "yt-dlp $_ytDlpVersion" : "yt-dlp not detected",
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => unawaited(_detectVersion()),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.refresh_rounded, size: 16, color: Design.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String description,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onPick,
    IconData pickIcon = Icons.folder_open_rounded,
    bool readOnly = false,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text)),
          const SizedBox(height: 2),
          Text(description, style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(130))),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: readOnly,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
                    filled: true,
                    fillColor: Design.text.withAlpha(10),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(icon: pickIcon, label: "Browse", onTap: onPick),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: Design.accent.withAlpha(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Design.text.withAlpha(16)),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: Design.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text)),
                    Text(subtitle, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(130))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: Design.text.withAlpha(140)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared building blocks ──────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: child,
    );
  }

  Widget _buildSectionLabel({required String label, required IconData icon, int? count}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
              fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Design.text),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
            child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildMiniLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
          fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Design.text.withAlpha(150)),
    );
  }

  Widget _segRail({
    required List<({String value, String label})> items,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((({String value, String label}) it) {
        final bool sel = it.value == current;
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onSelect(it.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? Design.accent.withAlpha(28) : Design.text.withAlpha(7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: sel ? Design.accent.withAlpha(90) : Design.text.withAlpha(16)),
            ),
            child: Text(
              it.label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 0.5,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                color: sel ? Design.accent : Design.text.withAlpha(180),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 15, color: value ? Design.accent : Design.text.withAlpha(140)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(130))),
                ],
              ),
            ),
            MiniToggleSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildMiniLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineField({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildMiniLabel(label),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
            filled: true,
            fillColor: Design.text.withAlpha(10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Small reusable button
// ─────────────────────────────────────────────

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Design.accent.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: Design.accent),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.accent)),
          ],
        ),
      ),
    );
  }
}
