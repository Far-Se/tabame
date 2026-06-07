import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

// ─────────────────────────────────────────────
//  Prefs keys (shared_preferences via Boxes.pref)
// ─────────────────────────────────────────────

const String _kWatchFolders = 'imgconv.watchFolders';
const String _kProfiles = 'imgconv.profiles';

// ─────────────────────────────────────────────
//  Encode helpers — ffmpeg CLI
//
//  ffmpeg is invoked via Process.run (direct) with a PowerShell fallback.
//  Source bytes are written to a temp file; ffmpeg writes to a second temp
//  file whose bytes are returned to the caller.
// ─────────────────────────────────────────────

/// Runs [args] through `ffmpeg` directly, or via PowerShell if the direct
/// call fails (e.g. ffmpeg not on PATH but available via winget shim).
Future<ProcessResult> _runFfmpeg(List<String> args) async {
  try {
    final ProcessResult r = await Process.run('ffmpeg', args);
    // ffmpeg exits 0 on success; non-zero means a real error
    if (r.exitCode == 0 || r.exitCode == 1) return r; // 1 = warnings only
    throw ProcessException('ffmpeg', args, r.stderr.toString(), r.exitCode);
  } catch (_) {
    // Fallback: run through PowerShell so the PATH inherited by child
    // processes (e.g. winget-managed ffmpeg) is used.
    final String escaped = args.map((String a) => '"$a"').join(' ');
    return Process.run(
      'powershell',
      <String>['-NoProfile', '-Command', 'ffmpeg $escaped'],
    );
  }
}

/// Builds the ffmpeg video-filter string for resize, or null if no resize.
String? _buildVfScale(ResizeMode mode, int percent, int targetWidth) {
  switch (mode) {
    case ResizeMode.percentage:
      if (percent == 100) return null;
      final double f = percent / 100.0;
      // Use iw/ih expressions so ffmpeg resolves dimensions itself
      return 'scale=iw*$f:ih*$f:flags=lanczos';
    case ResizeMode.targetWidth:
      // Keep aspect ratio; pad to even dimensions required by some codecs
      return 'scale=$targetWidth:-2:flags=lanczos';
    case ResizeMode.none:
      return null;
  }
}

/// Converts [src] bytes using ffmpeg and returns the encoded bytes.
///
/// Throws on ffmpeg error.
Future<Uint8List> _ffmpegEncode({
  required Uint8List src,
  required String srcExt, // e.g. '.png'
  required ImgFormat format,
  required int quality,
  required ResizeMode resizeMode,
  required int resizePercent,
  required int resizeWidth,
}) async {
  final Directory tmp = await Directory.systemTemp.createTemp('imgconv_');
  try {
    // Write source to a temp file with its original extension so ffmpeg
    // can auto-detect the codec.
    final File inFile = File('${tmp.path}\\in$srcExt');
    await inFile.writeAsBytes(src);

    final String outExt = '.${format.ext}';
    final File outFile = File('${tmp.path}\\out$outExt');

    // ── Build ffmpeg args ────────────────────────────────────────────────
    final List<String> args = <String>[
      '-y', // overwrite without asking
      '-i', inFile.path,
    ];

    // Video filter (resize)
    final String? vf = _buildVfScale(resizeMode, resizePercent, resizeWidth);
    if (vf != null) {
      args.addAll(<String>['-vf', vf]);
    }

    // Codec / quality flags per format
    switch (format) {
      case ImgFormat.jpg:
        // qscale:v 2–31; map quality 1-100 → qscale 31-2
        final int q = (31 - (quality / 100.0 * 29).round()).clamp(2, 31);
        args.addAll(<String>['-q:v', '$q']);
        break;
      case ImgFormat.png:
        // PNG is lossless; compression level 0-9 via -compression_level
        args.addAll(<String>['-compression_level', '6']);
        break;
      case ImgFormat.webp:
        args.addAll(<String>['-quality', '$quality']);
        break;
    }

    args.add(outFile.path);

    final ProcessResult result = await _runFfmpeg(args);
    if (result.exitCode != 0) {
      throw Exception('ffmpeg failed (exit ${result.exitCode}):\n${result.stderr}');
    }

    return await outFile.readAsBytes();
  } finally {
    tmp.delete(recursive: true).catchError((_) => Directory(''));
  }
}

// ─────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────

enum ImgFormat { jpg, png, webp }

extension ImgFormatExt on ImgFormat {
  String get label => name.toUpperCase();
  String get ext => name;
}

enum ResizeMode { none, percentage, targetWidth }

class ConvertProfile {
  ConvertProfile({
    required this.name,
    required this.format,
    required this.quality,
    required this.resizeMode,
    this.resizePercent = 100,
    this.resizeWidth,
    required this.outputMode,
    this.outputFolder,
  });

  String name;
  ImgFormat format;
  int quality; // 0-100
  ResizeMode resizeMode;
  int resizePercent;
  int? resizeWidth; // target width in px (ResizeMode.targetWidth only)
  OutputMode outputMode;
  String? outputFolder;

  // ── Serialise ──────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'format': format.index,
        'quality': quality,
        'resizeMode': resizeMode.index,
        'resizePercent': resizePercent,
        'resizeWidth': resizeWidth,
        'outputMode': outputMode.index,
        'outputFolder': outputFolder,
      };

  factory ConvertProfile.fromJson(Map<String, dynamic> j) => ConvertProfile(
        name: j['name'] as String? ?? 'Profile',
        format: ImgFormat.values[j['format'] as int? ?? 0],
        quality: j['quality'] as int? ?? 90,
        resizeMode: ResizeMode.values[(j['resizeMode'] as int? ?? 0).clamp(0, ResizeMode.values.length - 1)],
        resizePercent: j['resizePercent'] as int? ?? 100,
        resizeWidth: j['resizeWidth'] as int?,
        outputMode: OutputMode.values[j['outputMode'] as int? ?? 0],
        outputFolder: j['outputFolder'] as String?,
      );

  ConvertProfile copyWith({
    String? name,
    ImgFormat? format,
    int? quality,
    ResizeMode? resizeMode,
    int? resizePercent,
    int? resizeWidth,
    OutputMode? outputMode,
    String? outputFolder,
  }) =>
      ConvertProfile(
        name: name ?? this.name,
        format: format ?? this.format,
        quality: quality ?? this.quality,
        resizeMode: resizeMode ?? this.resizeMode,
        resizePercent: resizePercent ?? this.resizePercent,
        resizeWidth: resizeWidth ?? this.resizeWidth,
        outputMode: outputMode ?? this.outputMode,
        outputFolder: outputFolder ?? this.outputFolder,
      );
}

enum OutputMode { clipboard, sameFolder, specificFolder }

extension OutputModeExt on OutputMode {
  String get label {
    switch (this) {
      case OutputMode.clipboard:
        return 'Copy to clipboard';
      case OutputMode.sameFolder:
        return 'Same folder as original';
      case OutputMode.specificFolder:
        return 'Specific folder…';
    }
  }

  IconData get icon {
    switch (this) {
      case OutputMode.clipboard:
        return Icons.copy_outlined;
      case OutputMode.sameFolder:
        return Icons.folder_outlined;
      case OutputMode.specificFolder:
        return Icons.drive_folder_upload_outlined;
    }
  }
}

// ─────────────────────────────────────────────
//  Persistence helpers (Boxes.pref = shared_preferences)
// ─────────────────────────────────────────────

class _ImgConvPrefs {
  static List<String> loadWatchFolders() {
    final String? raw = Boxes.pref.getString(_kWatchFolders);
    if (raw == null || raw.isEmpty) return <String>[];
    return raw.split('|').where((String s) => s.isNotEmpty).toList();
  }

  static Future<void> saveWatchFolders(List<String> folders) async {
    await Boxes.pref.setString(_kWatchFolders, folders.join('|'));
  }

  static List<ConvertProfile> loadProfiles() {
    final String? raw = Boxes.pref.getString(_kProfiles);
    if (raw == null || raw.isEmpty) return <ConvertProfile>[];
    try {
      final List<dynamic> list = (raw.split('\x1E')).map((String s) {
        // Very small custom serialisation to avoid adding json_serializable
        final Map<String, dynamic> m = <String, dynamic>{};
        for (final String pair in s.split('\x1F')) {
          final int sep = pair.indexOf('=');
          if (sep == -1) continue;
          final String k = pair.substring(0, sep);
          final String v = pair.substring(sep + 1);
          // Try int / bool / null, else keep String
          if (v == 'null') {
            m[k] = null;
          } else if (v == 'true') {
            m[k] = true;
          } else if (v == 'false') {
            m[k] = false;
          } else {
            final int? intVal = int.tryParse(v);
            m[k] = intVal ?? v;
          }
        }
        return m;
      }).toList();
      return list.map((dynamic e) => ConvertProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return <ConvertProfile>[];
    }
  }

  static Future<void> saveProfiles(List<ConvertProfile> profiles) async {
    final String raw = profiles.map((ConvertProfile p) {
      final Map<String, dynamic> j = p.toJson();
      return j.entries.map((MapEntry<String, dynamic> e) => '${e.key}=${e.value}').join('\x1F');
    }).join('\x1E');
    await Boxes.pref.setString(_kProfiles, raw);
  }
}

// ─────────────────────────────────────────────
//  Supported image extensions
// ─────────────────────────────────────────────

const Set<String> _kImageExtensions = <String>{
  '.jpg', '.jpeg', '.png', '.webp', '.jfif', '.bmp', '.gif', '.tiff', '.tif', //
};

String _ext(String path) {
  final int i = path.lastIndexOf('.');
  return i == -1 ? '' : path.substring(i).toLowerCase();
}

bool _isImage(String path) => _kImageExtensions.contains(_ext(path));

// ─────────────────────────────────────────────
//  Button
// ─────────────────────────────────────────────

class ImageConverterButton extends StatelessWidget {
  const ImageConverterButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: 'Image Converter',
      icon: const Icon(Icons.transform_rounded),
      child: () => const ImageConverterPanel(),
    );
  }
}

// ─────────────────────────────────────────────
//  Top-level panel — main page
// ─────────────────────────────────────────────

enum _Page { main, settings }

class ImageConverterPanel extends StatefulWidget {
  const ImageConverterPanel({super.key});

  @override
  State<ImageConverterPanel> createState() => _ImageConverterPanelState();
}

class _ImageConverterPanelState extends State<ImageConverterPanel> {
  _Page _page = _Page.main;

  // Images gathered in the main page
  File? _clipboardImageFile; // temporary file written from clipboard bytes
  Uint8List? _clipboardBytes;
  final List<File> _files = <File>[];
  final Set<int> _selected = <int>{};

  bool _loadingClipboard = true;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
    _loadWatchedFolderImages();
  }

  @override
  void dispose() {
    // Clean up temp clipboard file if any
    _clipboardImageFile?.delete().catchError((_) => File(''));
    super.dispose();
  }

  // ── Data loading ──────────────────────────

  Future<void> _checkClipboard() async {
    try {
      final Uint8List? bytes = await ClipboardExtended.pasteImage();
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        // Persist clipboard bytes to a temp file so ffmpeg can read them
        // by path. We detect whether the data is a raw DIB (no PNG header)
        // and write it as BMP in that case; otherwise treat it as PNG.
        final Directory tmpDir = await Directory.systemTemp.createTemp('imgconv_cb_');
        final bool isPng = bytes.length > 8 &&
            bytes[0] == 0x89 &&
            bytes[1] == 0x50 && // P
            bytes[2] == 0x4E && // N
            bytes[3] == 0x47; // G
        final String ext = isPng ? '.png' : '.bmp';
        final File tmpFile = File('${tmpDir.path}\\clipboard$ext');
        await tmpFile.writeAsBytes(bytes);
        setState(() {
          _clipboardImageFile = tmpFile;
          _clipboardBytes = bytes;
          _loadingClipboard = false;
        });
      } else {
        setState(() => _loadingClipboard = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClipboard = false);
    }
  }

  void _loadWatchedFolderImages() {
    final List<String> folders = _ImgConvPrefs.loadWatchFolders();
    final List<File> found = <File>[];
    for (final String folderPath in folders) {
      final Directory dir = Directory(folderPath);
      if (!dir.existsSync()) continue;
      found.addAll(
        dir.listSync(followLinks: false).whereType<File>().where((File f) => _isImage(f.path)).toList()
          ..sort((File a, File b) => b.statSync().modified.compareTo(a.statSync().modified)),
      );
    }
    if (mounted) {
      setState(() => _files
        ..clear()
        ..addAll(found));
    }
  }

  // ── File picking ──────────────────────────

  void _pickFile() {
    QuickMenuFunctions.keepOpen = true;
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Image Files': '*.jpg;*.jpeg;*.png;*.webp;*.jfif;*.bmp;*.gif;*.tiff',
        'All Files': '*.*',
      }
      ..defaultFilterIndex = 0
      ..title = 'Select Image';
    final File? result = picker.getFile();
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    if (result == null) return;
    setState(() {
      if (!_files.any((File f) => f.path == result.path)) {
        _files.insert(0, result);
      }
    });
  }

  void _pickFolder() {
    QuickMenuFunctions.keepOpen = true;
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select Folder';
    final Directory? dir = dirPicker.getDirectory();
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || !dir.existsSync()) return;
    final List<File> found = dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((File f) => _isImage(f.path))
        .toList()
      ..sort((File a, File b) => b.statSync().modified.compareTo(a.statSync().modified));
    setState(() {
      for (final File f in found) {
        if (!_files.any((File e) => e.path == f.path)) {
          _files.add(f);
        }
      }
    });
  }

  // ── Copy helpers ──────────────────────────

  /// Copies the raw image bytes to the clipboard as a BMP/DIB (what Windows
  /// expects for CF_DIB). Uses an ffmpeg BMP re-encode pass identical to the
  /// one used in the converter.
  Future<void> _copyImageToClipboard(File file) async {
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('imgconv_cp_');
      final String srcExt = file.path.contains('.') ? '.${file.path.split('.').last.toLowerCase()}' : '.png';
      final File tmpSrc = File('${tmp.path}\\src$srcExt');
      await tmpSrc.writeAsBytes(await file.readAsBytes());
      final File tmpBmp = File('${tmp.path}\\out.bmp');
      final ProcessResult r = await _runFfmpeg(<String>['-y', '-i', tmpSrc.path, tmpBmp.path]);
      if (r.exitCode != 0) throw Exception('ffmpeg failed: ${r.stderr}');
      await ClipboardExtended.copyImage(await tmpBmp.readAsBytes());
    } catch (_) {
      // Silently ignore — could add a snackbar here if desired
    } finally {
      tmp?.delete(recursive: true).catchError((_) => Directory(''));
    }
  }

  /// Copies the file path string to the system clipboard.
  Future<void> _copyImageFileToClipboard(File file) async {
    try {
      await ClipboardExtension.copyFile(file.path);
    } catch (_) {}
  }

  // ── Convert ───────────────────────────────

  void _openConverter({bool clipboardImage = false}) {
    if (clipboardImage && _clipboardImageFile != null) {
      showQuickMenuModal(
        context: context,
        child: _ConverterPage(
          files: const <File>[],
          clipboardBytes: _clipboardBytes,
          clipboardTempFile: _clipboardImageFile,
        ),
      ).then((_) {
        if (!mounted) return;
        _checkClipboard();
        _loadWatchedFolderImages();
      });
      return;
    }
    if (_selected.isEmpty) return;
    final List<File> targets = <File>[];
    for (final int i in _selected) {
      targets.add(_files[i]);
    }
    showQuickMenuModal(
      context: context,
      child: _ConverterPage(files: targets),
    ).then((_) {
      if (!mounted) return;
      _checkClipboard();
      _loadWatchedFolderImages();
    });
  }
  // ── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_page == _Page.settings) {
      return _SettingsSubPage(
        onBack: () {
          setState(() => _page = _Page.main);
          _loadWatchedFolderImages();
        },
      );
    }
    return _buildMainPage(context);
  }

  Widget _buildMainPage(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header ──
        PanelHeader(
          title: 'Image Converter',
          accent: accent,
          icon: Icons.transform_rounded,
          extraActions: <Widget>[
            IconButton(
              icon: const Icon(Icons.image_outlined, size: 16),
              tooltip: 'Add Image',
              onPressed: _pickFile,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              tooltip: 'Add Folder',
              onPressed: _pickFolder,
            ),
            if (_selected.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                tooltip: 'Convert (${_selected.length})',
                onPressed: () => _openConverter(),
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 16),
              tooltip: 'Watched folders',
              onPressed: () => setState(() => _page = _Page.settings),
            ),
          ],
        ),

        const SizedBox(height: 4),

        // ── List ──
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: <Widget>[
              // Clipboard entry
              if (_loadingClipboard)
                _ClipboardLoadingTile(accent: accent, onSurface: onSurface)
              else if (_clipboardBytes != null)
                _ClipboardImageTile(
                  bytes: _clipboardBytes!,
                  accent: accent,
                  onSurface: onSurface,
                  onConvert: () => _openConverter(clipboardImage: true),
                ),

              // File entries
              if (_files.isEmpty && !_loadingClipboard && _clipboardBytes == null)
                const _Hint(
                  icon: Icons.image_search_outlined,
                  message: 'Add images or folders above.\nYou can also set watched folders in settings.',
                )
              else
                ..._files.asMap().entries.map((MapEntry<int, File> entry) {
                  final int i = entry.key;
                  final File f = entry.value;
                  final bool selected = _selected.contains(i);
                  return _FileRow(
                    file: f,
                    selected: selected,
                    accent: accent,
                    onSurface: onSurface,
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selected.remove(i);
                        } else {
                          _selected.add(i);
                        }
                      });
                    },
                    onConvertSingle: () {
                      setState(() {
                        _selected
                          ..clear()
                          ..add(i);
                      });
                      _openConverter();
                    },
                    onRemove: () => setState(() {
                      _files.removeAt(i);
                      _selected.remove(i);
                    }),
                    onCopyImage: () => _copyImageToClipboard(f),
                    onCopyImageFile: () => _copyImageFileToClipboard(f),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Settings sub-page (watched folders)
// ─────────────────────────────────────────────

class _SettingsSubPage extends StatefulWidget {
  const _SettingsSubPage({required this.onBack});
  final VoidCallback onBack;

  @override
  State<_SettingsSubPage> createState() => _SettingsSubPageState();
}

class _SettingsSubPageState extends State<_SettingsSubPage> {
  List<String> _folders = <String>[];

  @override
  void initState() {
    super.initState();
    _folders = _ImgConvPrefs.loadWatchFolders();
  }

  void _addFolder() {
    QuickMenuFunctions.keepOpen = true;
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select folder to watch';
    final Directory? dir = picker.getDirectory();
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || dir.path.isEmpty) return;
    if (!_folders.contains(dir.path)) {
      setState(() => _folders.add(dir.path));
      _ImgConvPrefs.saveWatchFolders(_folders);
    }
  }

  void _removeFolder(int index) {
    setState(() => _folders.removeAt(index));
    _ImgConvPrefs.saveWatchFolders(_folders);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Watched Folders',
          accent: accent,
          icon: Icons.folder_special_outlined,
          extraActions: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              tooltip: 'Back',
              splashRadius: 18,
              onPressed: widget.onBack,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: _ToolbarButton(
            icon: Icons.add_rounded,
            label: 'Add Watched Folder',
            accent: accent,
            onTap: _addFolder,
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: _folders.isEmpty
              ? const _Hint(
                  icon: Icons.folder_off_outlined,
                  message: 'No watched folders.\nImages in watched folders will appear on the main page.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                  itemCount: _folders.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _FolderRow(
                      path: _folders[index],
                      accent: accent,
                      onSurface: onSurface,
                      onRemove: () => _removeFolder(index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Converter page (full screen push)
// ─────────────────────────────────────────────

class _ConverterPage extends StatefulWidget {
  const _ConverterPage({
    required this.files,
    this.clipboardBytes,
    this.clipboardTempFile,
  });

  final List<File> files;
  final Uint8List? clipboardBytes;

  /// Temp file on disk containing the clipboard image — used by ffmpeg.
  final File? clipboardTempFile;

  @override
  State<_ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<_ConverterPage> {
  // ── Conversion state ──────────────────────
  ImgFormat _format = ImgFormat.jpg;
  int _quality = 90;
  ResizeMode _resizeMode = ResizeMode.none;
  int _resizePercent = 50;
  int _resizeWidth = 1920; // target width in px (ResizeMode.targetWidth)
  OutputMode _outputMode = OutputMode.clipboard;
  String? _outputFolder;

  // ── Profile state ─────────────────────────
  List<ConvertProfile> _profiles = <ConvertProfile>[];
  String? _activeProfileName;

  bool _converting = false;
  String? _statusMessage;
  bool _statusIsError = false;
  int _convertProgress = 0;
  int _convertTotal = 0;

  // ── Text controllers ──────────────────────
  late final TextEditingController _widthCtrl;
  late final TextEditingController _percentCtrl;
  late final TextEditingController _profileNameCtrl;

  @override
  void initState() {
    super.initState();
    _widthCtrl = TextEditingController(text: '$_resizeWidth');
    _percentCtrl = TextEditingController(text: '$_resizePercent');
    _profileNameCtrl = TextEditingController();
    _profiles = _ImgConvPrefs.loadProfiles();
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _percentCtrl.dispose();
    _profileNameCtrl.dispose();
    super.dispose();
  }

  // ── Profile helpers ───────────────────────

  void _applyProfile(ConvertProfile p) {
    setState(() {
      _activeProfileName = p.name;
      _format = p.format;
      _quality = p.quality;
      _resizeMode = p.resizeMode;
      _resizePercent = p.resizePercent;
      _resizeWidth = p.resizeWidth ?? 1920;
      // "Same folder as original" is invalid for clipboard sources — fall back
      // to clipboard output mode in that case.
      final bool isClipboardSource = widget.clipboardBytes != null;
      _outputMode = (isClipboardSource && p.outputMode == OutputMode.sameFolder) ? OutputMode.clipboard : p.outputMode;
      _outputFolder = p.outputFolder;
      _widthCtrl.text = '$_resizeWidth';
      _percentCtrl.text = '$_resizePercent';
    });
  }

  void _saveProfile() {
    final String name = _profileNameCtrl.text.trim();
    if (name.isEmpty) return;
    final ConvertProfile profile = ConvertProfile(
      name: name,
      format: _format,
      quality: _quality,
      resizeMode: _resizeMode,
      resizePercent: _resizePercent,
      resizeWidth: _resizeWidth,
      outputMode: _outputMode,
      outputFolder: _outputFolder,
    );
    setState(() {
      _profiles.removeWhere((ConvertProfile p) => p.name == name);
      _profiles.add(profile);
      _activeProfileName = name;
      _profileNameCtrl.clear();
    });
    _ImgConvPrefs.saveProfiles(_profiles);
  }

  void _deleteProfile(String name) {
    setState(() {
      _profiles.removeWhere((ConvertProfile p) => p.name == name);
      if (_activeProfileName == name) _activeProfileName = null;
    });
    _ImgConvPrefs.saveProfiles(_profiles);
  }

  // ── Output folder picker ──────────────────

  void _pickOutputFolder() {
    QuickMenuFunctions.keepOpen = true;
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select output folder';
    final Directory? dir = picker.getDirectory();

    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || dir.path.isEmpty) return;
    setState(() => _outputFolder = dir.path);
  }

  // ── Convert ───────────────────────────────

  /// Builds a collision-free output [File] for the given source index.
  File _outputFile(int sourceIndex, String dir, {bool isClipboardEntry = false}) {
    final bool isClipboard = isClipboardEntry || sourceIndex < 0 || sourceIndex >= widget.files.length;
    final String baseName = isClipboard
        ? 'clipboard_image'
        : widget.files[sourceIndex].uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');

    String stem = baseName;
    if (!isClipboard && _outputMode == OutputMode.sameFolder) {
      final String srcExt = _ext(widget.files[sourceIndex].path);
      final bool clash = srcExt == '.${_format.ext}' ||
          (srcExt == '.jpg' && _format == ImgFormat.jpg) ||
          (srcExt == '.jpeg' && _format == ImgFormat.jpg);
      if (clash) stem = '${baseName}_converted';
    }

    File out = File('$dir\\$stem.${_format.ext}');
    int n = 1;
    while (out.existsSync() && (isClipboard || out.path != widget.files[sourceIndex].path)) {
      out = File('$dir\\${stem}_$n.${_format.ext}');
      n++;
    }
    return out;
  }

  String _outputDir(int sourceIndex, {bool isClipboardEntry = false}) {
    if (_outputMode == OutputMode.specificFolder && _outputFolder != null) {
      return _outputFolder!;
    }
    if (!isClipboardEntry && sourceIndex >= 0 && sourceIndex < widget.files.length) {
      return widget.files[sourceIndex].parent.path;
    }
    // clipboard + sameFolder (or no valid file) → Desktop
    return '${Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Public'}\\Desktop';
  }

  Future<void> _doConvert() async {
    // ── Collect sources ──────────────────────────────────────────────────────
    // Each entry carries a source File (preferred, for ffmpeg) or raw bytes,
    // a display label, and the original extension so ffmpeg can auto-detect
    // the input codec.
    final List<({File? file, Uint8List? bytes, String label, String srcExt})> sources =
        <({File? file, Uint8List? bytes, String label, String srcExt})>[];

    if (widget.clipboardTempFile != null) {
      final String ext = _ext(widget.clipboardTempFile!.path);
      sources.add((
        file: widget.clipboardTempFile,
        bytes: null,
        label: 'clipboard',
        srcExt: ext.isEmpty ? '.bmp' : ext,
      ));
    } else if (widget.clipboardBytes != null) {
      // Fallback: write raw clipboard bytes to a temp BMP for ffmpeg
      final Directory tmpDir = await Directory.systemTemp.createTemp('imgconv_cb2_');
      final File tmpFile = File('${tmpDir.path}\\clipboard.bmp');
      await tmpFile.writeAsBytes(widget.clipboardBytes!);
      sources.add((file: tmpFile, bytes: null, label: 'clipboard', srcExt: '.bmp'));
    }
    for (final File f in widget.files) {
      try {
        sources.add((
          file: f,
          bytes: null,
          label: f.uri.pathSegments.last,
          srcExt: _ext(f.path).isEmpty ? '.png' : _ext(f.path),
        ));
      } catch (_) {
        // Skip unreadable files — will be reported as errors below
      }
    }

    setState(() {
      _converting = true;
      _statusMessage = null;
      _statusIsError = false;
      _convertProgress = 0;
      _convertTotal = sources.length;
    });

    // Nothing to convert — surface a clear message instead of crashing.
    if (sources.isEmpty) {
      setState(() {
        _converting = false;
        _statusMessage = 'No images to convert.';
        _statusIsError = true;
      });
      return;
    }

    final List<String> savedPaths = <String>[];
    final List<String> errors = <String>[];
    final bool hasClipboardSource = widget.clipboardTempFile != null || widget.clipboardBytes != null;

    for (int i = 0; i < sources.length; i++) {
      if (!mounted) break;
      setState(() => _convertProgress = i);

      final File? srcFile = sources[i].file;
      final String label = sources[i].label;
      final String srcExt = sources[i].srcExt;
      // fileIndex is the index into widget.files; clipboard is index -1 (sentinel).
      // When hasClipboardSource the first source (i==0) is the clipboard entry,
      // so file entries start at i==1 → fileIndex = i-1 = 0, 1, 2, …
      // For clipboard itself fileIndex = -1, which _outputDir/_outputFile handle.
      final int fileIndex = hasClipboardSource ? i - 1 : i;
      final bool isClipboardEntry = hasClipboardSource && i == 0;

      try {
        final Uint8List srcBytes = srcFile != null ? await srcFile.readAsBytes() : sources[i].bytes!;

        final Uint8List encoded = await _ffmpegEncode(
          src: srcBytes,
          srcExt: srcExt,
          format: _format,
          quality: _quality,
          resizeMode: _resizeMode,
          resizePercent: _resizePercent,
          resizeWidth: _resizeWidth,
        );

        if (_outputMode == OutputMode.clipboard) {
          // ClipboardExtended.copyImage on Windows requires raw BMP/DIB bytes
          // (CF_DIB). Formats like WebP or PNG cannot be pasted directly — we
          // re-encode the output to BMP via a second ffmpeg pass, then copy.
          Directory? tmpOut;
          try {
            tmpOut = await Directory.systemTemp.createTemp('imgconv_out_');
            final File tmpSrcFile = File('${tmpOut.path}\\src.${_format.ext}');
            await tmpSrcFile.writeAsBytes(encoded);
            final File tmpBmpFile = File('${tmpOut.path}\\out.bmp');
            final ProcessResult bmpResult = await _runFfmpeg(<String>[
              '-y',
              '-i',
              tmpSrcFile.path,
              tmpBmpFile.path,
            ]);
            if (bmpResult.exitCode != 0) {
              throw Exception('ffmpeg BMP pass failed (exit ${bmpResult.exitCode}):\n${bmpResult.stderr}');
            }
            final Uint8List bmpBytes = await tmpBmpFile.readAsBytes();
            await ClipboardExtended.copyImage(bmpBytes);
          } finally {
            tmpOut?.delete(recursive: true).catchError((_) => Directory(''));
          }
          savedPaths.add('clipboard');
        } else {
          final String dir = _outputDir(fileIndex, isClipboardEntry: isClipboardEntry);
          await Directory(dir).create(recursive: true);
          final File outFile = _outputFile(fileIndex, dir, isClipboardEntry: isClipboardEntry);
          await outFile.writeAsBytes(encoded);
          savedPaths.add(outFile.path);
        }
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    if (!mounted) return;

    String msg;
    bool isError = false;
    if (errors.isEmpty) {
      if (_outputMode == OutputMode.clipboard) {
        msg = savedPaths.length == 1
            ? 'Copied to clipboard!'
            : 'Last of ${savedPaths.length} images copied to clipboard.';
      } else {
        msg = 'Saved ${savedPaths.length} file${savedPaths.length == 1 ? '' : 's'}.';
        if (savedPaths.length == 1) msg += '\n${savedPaths.first}';
      }
    } else if (savedPaths.isEmpty) {
      msg = 'Failed:\n${errors.first}';
      isError = true;
    } else {
      msg = 'Saved ${savedPaths.length}, ${errors.length} failed:\n${errors.first}';
      isError = true;
    }

    setState(() {
      _converting = false;
      _convertProgress = _convertTotal;
      _statusMessage = msg;
      _statusIsError = isError;
    });
  }

  // ── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Header ──
          PanelHeader(
            title:
                'Convert  •  ${widget.clipboardBytes != null ? 'Clipboard' : '${widget.files.length} image${widget.files.length == 1 ? '' : 's'}'}',
            accent: accent,
            icon: Icons.auto_fix_high_rounded,
            extraActions: <Widget>[
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Close',
                splashRadius: 18,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── Profiles row ──
                  if (_profiles.isNotEmpty) ...<Widget>[
                    _SectionLabel(label: 'Profiles', accent: accent),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _profiles.map((ConvertProfile p) {
                        final bool active = _activeProfileName == p.name;
                        return _ProfileChip(
                          label: p.name,
                          active: active,
                          accent: accent,
                          onTap: () => _applyProfile(p),
                          onDelete: () => _deleteProfile(p.name),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Format ──
                  _SectionLabel(label: 'Output Format', accent: accent),
                  const SizedBox(height: 6),
                  Row(
                    children: ImgFormat.values.map((ImgFormat f) {
                      final bool active = _format == f;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: _FormatButton(
                            label: f.label,
                            active: active,
                            accent: accent,
                            onTap: () => setState(() => _format = f),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),

                  // ── Quality ──
                  Row(
                    children: <Widget>[
                      _SectionLabel(label: 'Quality', accent: accent),
                      const Spacer(),
                      Text('$_quality%',
                          style:
                              TextStyle(fontSize: Design.baseFontSize + 2, color: accent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: accent,
                      thumbColor: accent,
                      inactiveTrackColor: accent.withAlpha(40),
                      overlayColor: accent.withAlpha(30),
                    ),
                    child: Slider(
                      value: _quality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: (double v) => setState(() => _quality = v.round()),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Resize ──
                  _SectionLabel(label: 'Resize', accent: accent),
                  const SizedBox(height: 6),

                  // Mode toggle
                  Row(
                    children: ResizeMode.values.map((ResizeMode m) {
                      final bool active = _resizeMode == m;
                      final String label = m == ResizeMode.none
                          ? 'None'
                          : m == ResizeMode.percentage
                              ? 'Percentage'
                              : 'Target Width';
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: _FormatButton(
                            label: label,
                            active: active,
                            accent: accent,
                            onTap: () => setState(() => _resizeMode = m),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Resize controls
                  if (_resizeMode == ResizeMode.percentage) ...<Widget>[
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _IntField(
                            controller: _percentCtrl,
                            label: 'Percent %',
                            accent: accent,
                            onSurface: onSurface,
                            onChanged: (int v) => setState(() => _resizePercent = v.clamp(1, 1000)),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (_resizeMode == ResizeMode.targetWidth) ...<Widget>[
                    const SizedBox(height: 10),
                    _IntField(
                      controller: _widthCtrl,
                      label: 'Target Width (px)  —  height scales automatically',
                      accent: accent,
                      onSurface: onSurface,
                      onChanged: (int v) => setState(() => _resizeWidth = v.clamp(1, 99999)),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Output ──
                  _SectionLabel(label: 'Output', accent: accent),
                  const SizedBox(height: 6),
                  Column(
                    children: OutputMode.values
                        // "Same folder as original" is meaningless for a clipboard
                        // source — hide it so the user can't select a broken option.
                        .where((OutputMode m) => !(widget.clipboardBytes != null && m == OutputMode.sameFolder))
                        .map((OutputMode m) {
                      return _OutputModeRow(
                        mode: m,
                        selected: _outputMode == m,
                        accent: accent,
                        onSurface: onSurface,
                        outputFolder: _outputFolder,
                        onTap: () {
                          setState(() => _outputMode = m);
                          if (m == OutputMode.specificFolder) _pickOutputFolder();
                        },
                        onPickFolder: m == OutputMode.specificFolder ? _pickOutputFolder : null,
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // ── Save profile ──
                  _SectionLabel(label: 'Save as Profile', accent: accent),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _profileNameCtrl,
                          style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Profile name…',
                            hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(100)),
                            filled: true,
                            fillColor: accent.withAlpha(10),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label: Text('Save', style: TextStyle(fontSize: Design.baseFontSize + 2)),
                        style: TextButton.styleFrom(
                          backgroundColor: accent.withAlpha(20),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Progress bar (batch) ──
                  if (_converting && _convertTotal > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                'Converting…',
                                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(160)),
                              ),
                              Text(
                                '$_convertProgress / $_convertTotal',
                                style: TextStyle(fontSize: Design.baseFontSize + 1, color: accent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _convertTotal == 0 ? null : _convertProgress / _convertTotal,
                              backgroundColor: accent.withAlpha(25),
                              color: accent,
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Status message ──
                  if (_statusMessage != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_statusIsError ? Colors.red : accent).withAlpha(18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (_statusIsError ? Colors.red : accent).withAlpha(60)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            _statusIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                            size: 14,
                            color: _statusIsError ? Colors.red : accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: Design.baseFontSize + 2,
                                color: _statusIsError ? Colors.red.shade300 : accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Convert button ──
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _converting ? null : _doConvert,
                      icon: _converting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
                            )
                          : const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: Text(
                        _converting ? 'Converting…' : 'Convert',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
                                s.contains(WidgetState.disabled) ? accent.withAlpha(80) : accent),
                            foregroundColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surface),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
          fontSize: Design.baseFontSize + 1,
          fontWeight: FontWeight.w700,
          color: User.theme.text.withAlpha(150),
          letterSpacing: 0.4),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 13),
      label: Text(label, style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        backgroundColor: accent.withAlpha(18),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: active ? accent.withAlpha(30) : accent.withAlpha(8),
        foregroundColor: User.theme.text.withAlpha(150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: active ? BorderSide(color: accent.withAlpha(80), width: 1) : BorderSide.none,
        ),
      ),
      child: Text(label, style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600)),
    );
  }
}

class _IntField extends StatelessWidget {
  const _IntField({
    required this.controller,
    required this.label,
    required this.accent,
    required this.onSurface,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final Color accent;
  final Color onSurface;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface),
      onChanged: (String v) {
        final int? i = int.tryParse(v);
        if (i != null) onChanged(i);
      },
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(130)),
        filled: true,
        fillColor: accent.withAlpha(10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
        ),
      ),
    );
  }
}

// class _CheckRow extends StatelessWidget {
//   const _CheckRow({
//     required this.label,
//     required this.value,
//     required this.accent,
//     required this.onSurface,
//     required this.onChanged,
//   });

//   final String label;
//   final bool value;
//   final Color accent;
//   final Color onSurface;
//   final ValueChanged<bool> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       borderRadius: BorderRadius.circular(7),
//       onTap: () => onChanged(!value),
//       child: Padding(
//         padding: const EdgeInsets.symmetric(vertical: 4),
//         child: Row(
//           children: <Widget>[
//             SizedBox(
//               width: 18,
//               height: 18,
//               child: Checkbox(
//                 value: value,
//                 activeColor: accent,
//                 side: BorderSide(color: onSurface.withAlpha(120), width: 1.4),
//                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
//                 onChanged: (bool? v) => onChanged(v ?? false),
//                 visualDensity: VisualDensity.compact,
//                 materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//               ),
//             ),
//             const SizedBox(width: 8),
//             Text(label, style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(200))),
//           ],
//         ),
//       ),
//     );
//   }
// }

class _OutputModeRow extends StatefulWidget {
  const _OutputModeRow({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.outputFolder,
    required this.onTap,
    this.onPickFolder,
  });

  final OutputMode mode;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final String? outputFolder;
  final VoidCallback onTap;
  final VoidCallback? onPickFolder;

  @override
  State<_OutputModeRow> createState() => _OutputModeRowState();
}

class _OutputModeRowState extends State<_OutputModeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.accent.withAlpha(22)
                : _hovered
                    ? widget.accent.withAlpha(10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected ? widget.accent.withAlpha(80) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.mode.icon,
                size: 14,
                color: widget.selected ? widget.accent : widget.onSurface.withAlpha(140),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.mode.label,
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2,
                        fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                        color: widget.selected ? widget.onSurface : widget.onSurface.withAlpha(180),
                      ),
                    ),
                    if (widget.mode == OutputMode.specificFolder && widget.outputFolder != null)
                      Text(
                        widget.outputFolder!,
                        style: TextStyle(fontSize: Design.baseFontSize, color: widget.accent.withAlpha(180)),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (widget.mode == OutputMode.specificFolder && widget.selected)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 13),
                  tooltip: 'Change folder',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: widget.accent.withAlpha(180),
                  onPressed: widget.onPickFolder,
                ),
              if (widget.selected)
                Icon(Icons.radio_button_checked_rounded, size: 14, color: widget.accent)
              else
                Icon(Icons.radio_button_unchecked_rounded, size: 14, color: widget.onSurface.withAlpha(80)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatefulWidget {
  const _ProfileChip({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
    required this.onDelete,
  });

  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ProfileChip> createState() => _ProfileChipState();
}

class _ProfileChipState extends State<_ProfileChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: widget.active ? widget.accent.withAlpha(30) : widget.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.active ? widget.accent.withAlpha(120) : widget.accent.withAlpha(30),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                    color: widget.active ? widget.accent : widget.accent.withAlpha(180),
                  ),
                ),
              ),
            ),
            if (_hovered)
              InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                onTap: widget.onDelete,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 5, 7, 5),
                  child: Icon(Icons.close_rounded, size: 11, color: widget.accent.withAlpha(160)),
                ),
              )
            else
              const SizedBox(width: 7),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Main-page row widgets
// ─────────────────────────────────────────────

class _ClipboardLoadingTile extends StatelessWidget {
  const _ClipboardLoadingTile({required this.accent, required this.onSurface});
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(30)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
              width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent.withAlpha(160))),
          const SizedBox(width: 10),
          Text('Checking clipboard…',
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(140))),
        ],
      ),
    );
  }
}

class _ClipboardImageTile extends StatefulWidget {
  const _ClipboardImageTile({
    required this.bytes,
    required this.accent,
    required this.onSurface,
    required this.onConvert,
  });

  final Uint8List bytes;
  final Color accent;
  final Color onSurface;
  final VoidCallback onConvert;

  @override
  State<_ClipboardImageTile> createState() => _ClipboardImageTileState();
}

class _ClipboardImageTileState extends State<_ClipboardImageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered ? widget.accent.withAlpha(180) : widget.accent.withAlpha(60),
            width: _hovered ? 1.5 : 1,
          ),
          color: widget.accent.withAlpha(_hovered ? 14 : 8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onConvert,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    widget.bytes,
                    width: 56,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 40,
                      color: widget.accent.withAlpha(20),
                      child: Icon(Icons.broken_image_outlined, size: 18, color: widget.accent.withAlpha(100)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Clipboard Image',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.bytes.lengthInBytes ~/ 1024} KB  •  from clipboard',
                        style: TextStyle(fontSize: Design.baseFontSize, color: widget.onSurface.withAlpha(130)),
                      ),
                    ],
                  ),
                ),
                // Star badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.accent.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.star_rounded, size: 11, color: widget.accent),
                      const SizedBox(width: 3),
                      Text('Clipboard',
                          style: TextStyle(
                              fontSize: Design.baseFontSize, color: widget.accent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 130),
                  opacity: _hovered ? 1.0 : 0.4,
                  child: Icon(Icons.auto_fix_high_rounded, size: 15, color: widget.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onConvertSingle,
    required this.onRemove,
    required this.onCopyImage,
    required this.onCopyImageFile,
  });

  final File file;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onConvertSingle;
  final VoidCallback onRemove;
  final VoidCallback onCopyImage;
  final VoidCallback onCopyImageFile;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  /// Full filename, e.g. "testimage.webp"
  String get _name => widget.file.path.split(RegExp(r'[\\/]')).last;

  /// Extension including dot, e.g. ".webp" (lower-case).
  String get _ext {
    final String n = _name;
    final int dot = n.lastIndexOf('.');
    return dot == -1 ? '' : n.substring(dot).toLowerCase();
  }

  /// Stem without extension, e.g. "testimage".
  String get _stem {
    final String n = _name;
    final int dot = n.lastIndexOf('.');
    return dot == -1 ? n : n.substring(0, dot);
  }

  String get _dir => widget.file.parent.path;
  String get _fileSize {
    try {
      final int bytes = widget.file.statSync().size;
      if (bytes < 1024) return '$bytes B';
      final int kb = bytes ~/ 1024;
      if (kb < 1024) return '$kb KB';
      return '${(kb / 1024).toStringAsFixed(1)} MB';
    } catch (_) {
      return '--';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.selected
              ? widget.accent.withAlpha(22)
              : _hovered
                  ? widget.accent.withAlpha(10)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected ? widget.accent.withAlpha(80) : Colors.transparent,
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: <Widget>[
                // Animated accent bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  width: _hovered || widget.selected ? 2.5 : 0,
                  height: 20,
                  margin: EdgeInsets.only(right: (_hovered || widget.selected) ? 8 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Thumb
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.file(
                    widget.file,
                    width: 38,
                    height: 28,
                    fit: BoxFit.cover,
                    cacheWidth: 76,
                    errorBuilder: (_, __, ___) => Container(
                      width: 38,
                      height: 28,
                      color: widget.accent.withAlpha(15),
                      child: Icon(Icons.broken_image_outlined, size: 14, color: widget.accent.withAlpha(80)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // ── Info (File name & Directory) ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Extension-preserving overflow: stem is clipped, ext is
                      // always shown. e.g. "testest....webp" instead of "testest..."
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              _stem,
                              style: TextStyle(
                                fontSize: Design.baseFontSize + 2,
                                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                                color: widget.selected ? widget.onSurface : widget.onSurface.withAlpha(210),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (_ext.isNotEmpty)
                            Text(
                              _ext,
                              style: TextStyle(
                                fontSize: Design.baseFontSize + 2,
                                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                                color: widget.selected ? widget.onSurface : widget.onSurface.withAlpha(210),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        _dir,
                        style: TextStyle(fontSize: Design.baseFontSize, color: widget.onSurface.withAlpha(100)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 4),

                // ── File Size / Hover Actions Stack ──
                // On hover: show three icon buttons (copy image, copy file, convert).
                // At rest: show file size.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  width: _hovered ? 82 : 44,
                  height: 28,
                  // ClipRect ensures children never paint or lay out outside
                  // the container bounds during the width animation.
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: 82,
                      alignment: Alignment.centerRight,
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: <Widget>[
                          // File size — fades out on hover
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 130),
                            opacity: _hovered ? 0.0 : 1.0,
                            child: Text(
                              _fileSize,
                              style: TextStyle(
                                fontSize: Design.baseFontSize,
                                color: widget.onSurface.withAlpha(140),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                            ),
                          ),

                          // Action buttons — fade in on hover
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 130),
                            opacity: _hovered ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_hovered,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  _RowAction(
                                    icon: Icons.copy_rounded,
                                    tooltip: 'Copy image to clipboard',
                                    accent: widget.accent,
                                    onTap: widget.onCopyImage,
                                  ),
                                  _RowAction(
                                    icon: Icons.file_copy_outlined,
                                    tooltip: 'Copy image file',
                                    accent: widget.accent,
                                    onTap: widget.onCopyImageFile,
                                  ),
                                  _RowAction(
                                    icon: Icons.auto_fix_high_rounded,
                                    tooltip: 'Convert this image',
                                    accent: widget.accent,
                                    onTap: widget.onConvertSingle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Checkbox
                const SizedBox(width: 6),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Checkbox(
                    value: widget.selected,
                    activeColor: widget.accent,
                    side: BorderSide(color: widget.onSurface.withAlpha(100), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                    onChanged: (_) => widget.onTap(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({required this.icon, required this.tooltip, required this.accent, required this.onTap});
  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: accent.withAlpha(200)),
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.path,
    required this.accent,
    required this.onSurface,
    required this.onRemove,
  });

  final String path;
  final Color accent;
  final Color onSurface;
  final VoidCallback onRemove;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hovered = false;

  int get _imageCount {
    try {
      return Directory(widget.path)
          .listSync(followLinks: false)
          .whereType<File>()
          .where((File f) => _isImage(f.path))
          .length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(14) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: _hovered ? 2.5 : 0,
                height: 16,
                margin: EdgeInsets.only(right: _hovered ? 8 : 0),
                decoration: BoxDecoration(color: widget.accent, borderRadius: BorderRadius.circular(2)),
              ),
              Icon(Icons.folder_outlined, size: 15, color: _hovered ? widget.accent : widget.onSurface.withAlpha(140)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.path,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(200),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.accent.withAlpha(_hovered ? 35 : 18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_imageCount img',
                  style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w600, color: widget.accent),
                ),
              ),
              const SizedBox(width: 4),
              // Delete button — shown on hover
              AnimatedOpacity(
                duration: const Duration(milliseconds: 130),
                opacity: _hovered ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    tooltip: 'Remove watched folder',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    color: Colors.red.withAlpha(180),
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Shared empty-state hint
// ─────────────────────────────────────────────

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.onSurface.withAlpha(100)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: Design.baseFontSize + 2, color: Theme.of(context).colorScheme.onSurface.withAlpha(160)),
            ),
          ],
        ),
      ),
    );
  }
}
