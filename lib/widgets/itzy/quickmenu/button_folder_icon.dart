import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class FolderIconButton extends StatelessWidget {
  const FolderIconButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: 'Folder Icon',
        icon: const Icon(Icons.folder_special_rounded),
        child: () => const FolderIconWidget());
  }
}

class FolderIconWidget extends StatefulWidget {
  const FolderIconWidget({super.key});
  @override
  FolderIconWidgetState createState() => FolderIconWidgetState();
}

class FolderIconWidgetState extends State<FolderIconWidget> {
  String? _selectedFolderPath;
  String? _selectedImagePath;

  // remove.bg state
  bool _removeBgEnabled = false;
  bool _apiKeyVisible = false;
  late TextEditingController _apiKeyController;
  bool _isRemovingBg = false;
  String? _processedImagePath; // path after bg removal (temp file)

  bool _isProcessing = false;
  String? _statusMessage;
  bool _statusIsError = false;

  static const String _apiKeySettingsKey = 'removeBgApiKey';

  @override
  void initState() {
    super.initState();
    final String savedKey = Boxes.pref.getString(_apiKeySettingsKey) ?? '';
    _apiKeyController = TextEditingController(text: savedKey);
    if (savedKey.isNotEmpty) {
      _removeBgEnabled = true;
      _getRemoveBGCredits();
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _cleanUpTempFile();
    super.dispose();
  }

  void _cleanUpTempFile() {
    if (_processedImagePath != null) {
      try {
        final File f = File(_processedImagePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      _processedImagePath = null;
    }
  }

  Future<void> _pickFolder() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select folder to change icon';
    final Directory? dir = dirPicker.getDirectory();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || dir.path.isEmpty) return;
    setState(() {
      _selectedFolderPath = dir.path;
      _statusMessage = null;
    });
  }

  Future<void> _pickImage() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Image Files (*.png, *.webp, *.jpg, *.jpeg, *.jfif)': '*.png;*.webp;*.jpg;*.jpeg;*.jfif'
      }
      ..defaultFilterIndex = 0
      ..title = 'Select icon image';
    final File? result = file.getFile();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (result == null) return;
    _cleanUpTempFile();
    setState(() {
      _selectedImagePath = result.path;
      _statusMessage = null;
    });
  }

  void _onToggleRemoveBg(bool value) {
    setState(() {
      _removeBgEnabled = value;
      _statusMessage = null;
    });
  }

  int? _creditsLeft;
  void _saveApiKey() async {
    final String key = _apiKeyController.text.trim();
    Boxes.pref.setString(_apiKeySettingsKey, key);
    FocusScope.of(context).unfocus();
    setState(() {
      _statusMessage = key.isEmpty ? null : 'API key saved.';
      _statusIsError = false;
      _getRemoveBGCredits();
    });
  }

  Future<void> _getRemoveBGCredits() async {
    final RemoveBgBalance? result = await getRemoveBgBalance(_apiKeyController.text);
    if (result != null) {
      _creditsLeft = result.credits;
      if (mounted) setState(() {});
    }
  }

  Future<RemoveBgBalance?> getRemoveBgBalance(String apiKey) async {
    final Uri url = Uri.parse('https://api.remove.bg/v1.0/account');

    try {
      final http.Response response = await http.get(
        url,
        headers: <String, String>{'X-Api-Key': apiKey},
      );

      if (response.statusCode == 200) {
        // ignore: always_specify_types
        final jsonBody = jsonDecode(response.body);
        // ignore: always_specify_types
        final attributes = jsonBody?['data']?['attributes'];

        if (attributes != null) {
          return RemoveBgBalance.fromJson(attributes);
        }
      } else {
        print('Failed to fetch data. Status code: ${response.statusCode}');
        _creditsLeft = null;
      }
    } catch (e) {
      _creditsLeft = null;
      print('An error occurred: $e');
    }

    return null;
  }

  Future<void> _removeBackground() async {
    if (_selectedImagePath == null) return;
    final String apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter your remove.bg API key first.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isRemovingBg = true;
      _statusMessage = 'Removing background…';
      _statusIsError = false;
    });

    try {
      final Uint8List resultBytes = await _callRemoveBgApi(
        imagePath: _selectedImagePath!,
        apiKey: apiKey,
      );

      // Save result as a temp PNG in cache
      final String cacheDir = '${WinUtils.getTabameAppDataFolder()}\\cache\\folder_icons';
      final Directory dir = Directory(cacheDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      _cleanUpTempFile();
      final String tmpPath = '$cacheDir\\_rmbg_tmp_${_randomId()}.png';
      await File(tmpPath).writeAsBytes(resultBytes, flush: true);

      if (!mounted) return;
      setState(() {
        _processedImagePath = tmpPath;
        _statusMessage = 'Background removed! Ready to apply.';
        _statusIsError = false;
      });
    } on _RemoveBgException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.message;
        _statusIsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'remove.bg error: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isRemovingBg = false);
    }
  }

  // ── Apply icon ───────────────────────────────────────────────────────────────

  Future<void> _applyIcon() async {
    if (_selectedFolderPath == null || _selectedImagePath == null) return;

    // Use processed (bg-removed) image if available, otherwise original
    final String sourceImage =
        (_removeBgEnabled && _processedImagePath != null) ? _processedImagePath! : _selectedImagePath!;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      final String icoPath = await compute<Map<String, String>, String>(
        _processAndSaveIcon,
        <String, String>{
          'imagePath': sourceImage,
          'cacheDir': '${WinUtils.getTabameAppDataFolder()}\\cache\\folder_icons',
        },
      );

      await _applyDesktopIni(_selectedFolderPath!, icoPath);
      await Process.run('ie4uinit.exe', <String>['-show']);

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Icon applied successfully!';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Error: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    // The image to preview: processed > original
    final String? previewPath = _processedImagePath ?? _selectedImagePath;
    final bool bgRemoved = _removeBgEnabled && _processedImagePath != null;

    // Apply is only ready when bg-removal is on and NOT yet done → block until removed
    final bool pendingBgRemoval = _removeBgEnabled && _selectedImagePath != null && _processedImagePath == null;
    final bool canApply = _selectedFolderPath != null &&
        _selectedImagePath != null &&
        !_isProcessing &&
        !_isRemovingBg &&
        !pendingBgRemoval;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Folder Icon',
          icon: Icons.folder_special_rounded,
          extraActions: <Widget>[
            IconButton(
              icon: const Icon(Icons.info_outline, size: 16),
              tooltip: 'Info',
              onPressed: _showInfo,
            ),
          ],
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ── Step 1: Pick Folder ────────────────────────────────
                _StepCard(
                  step: 1,
                  label: 'Select Target Folder',
                  accent: accent,
                  onSurface: onSurface,
                  child: _PickerRow(
                    icon: Icons.folder_open_rounded,
                    value: _selectedFolderPath,
                    placeholder: 'No folder selected',
                    accent: accent,
                    onSurface: onSurface,
                    onTap: _pickFolder,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Step 2: Pick Image ─────────────────────────────────
                _StepCard(
                  step: 2,
                  label: 'Select Icon Image',
                  accent: accent,
                  onSurface: onSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _PickerRow(
                        icon: Icons.image_rounded,
                        value: _selectedImagePath?.split(RegExp(r'[\\/]')).last,
                        placeholder: 'No image selected',
                        accent: accent,
                        onSurface: onSurface,
                        onTap: _pickImage,
                      ),
                      if (previewPath != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Stack(
                          alignment: Alignment.topRight,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(previewPath),
                                key: ValueKey<String>(previewPath),
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                            ),
                            if (bgRemoved)
                              Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(200),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'BG removed',
                                  style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── Step 3: remove.bg (optional) ───────────────────────
                _StepCard(
                  step: 3,
                  label: 'Remove Background (optional)',
                  accent: accent,
                  onSurface: onSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Toggle row
                      Row(
                        children: <Widget>[
                          MiniToggleSwitch(
                            value: _removeBgEnabled,
                            onChanged: _onToggleRemoveBg,
                            activeThumbColor: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _creditsLeft == null ? 'Use remove.bg API' : "remove.bg ($_creditsLeft Credits Left)",
                              style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface),
                            ),
                          ),
                          if (_removeBgEnabled)
                            InkWell(
                              onTap: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  _apiKeyVisible ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                  size: 18,
                                  color: onSurface.withAlpha(160),
                                ),
                              ),
                            ),
                        ],
                      ),
                      // API key input (collapsible)
                      if (_removeBgEnabled) ...<Widget>[
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          child: _apiKeyVisible
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: TextField(
                                          controller: _apiKeyController,
                                          obscureText: true,
                                          style: TextStyle(
                                              fontSize: Design.baseFontSize + 2, color: onSurface),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: 'Paste your remove.bg API key…',
                                            hintStyle: TextStyle(
                                                fontSize: Design.baseFontSize + 2,
                                                color: onSurface.withAlpha(100)),
                                            filled: true,
                                            fillColor: accent.withAlpha(10),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide.none,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
                                            ),
                                          ),
                                          onSubmitted: (_) => _saveApiKey(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: _saveApiKey,
                                        tooltip: 'Save key',
                                        icon: const Icon(Icons.check_rounded, size: 16),
                                        style: IconButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(34, 34),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 10),
                        // Remove BG button
                        ElevatedButton.icon(
                          onPressed: (_selectedImagePath != null && !_isRemovingBg && !_isProcessing)
                              ? _removeBackground
                              : null,
                          icon: _isRemovingBg
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.surface,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high_rounded, size: 16),
                          label: Text(_isRemovingBg
                              ? 'Removing background…'
                              : bgRemoved
                                  ? 'Re-run remove.bg'
                                  : 'Remove Background'),
                          style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                              if (states.contains(WidgetState.disabled)) return onSurface.withAlpha(30);
                              return accent.withAlpha(200);
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                              if (states.contains(WidgetState.disabled)) return onSurface.withAlpha(80);
                              return Colors.white;
                            }),
                          ),
                        ),
                        if (pendingBgRemoval) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            'Run "Remove Background" before applying, or disable the toggle to use the original image.',
                            style: TextStyle(
                                fontSize: Design.baseFontSize,
                                color: onSurface.withAlpha(140),
                                height: 1.4),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Status message ─────────────────────────────────────
                if (_statusMessage != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_statusIsError ? Colors.red : Colors.green).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_statusIsError ? Colors.red : Colors.green).withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _statusIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: _statusIsError ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              color: _statusIsError ? Colors.red : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Apply button ───────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: canApply ? _applyIcon : null,
                  icon: _isProcessing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.surface,
                          ),
                        )
                      : const Icon(Icons.folder_special_rounded, size: 16),
                  label: Text(_isProcessing ? 'Applying…' : 'Apply Icon'),
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) return onSurface.withAlpha(30);
                      return accent;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) return onSurface.withAlpha(80);
                      return Theme.of(context).colorScheme.surface;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showInfo() {
    showQuickMenuModal(
        context: context,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            // ── Header ──
            PanelHeader(
              title: 'Info',
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
                    const SizedBox(height: 6),
                    infoButton(
                        'Use an AI image generator to create a folder design template, then generate multiple variations with different text and color schemes so each folder visually matches its corresponding directory.'),
                    const SizedBox(height: 6),
                    infoButton(
                        'The image will be auto-cropped, resized to 256×256 and saved as .ico. A hidden desktop.ini will be written inside the selected folder that will change the folder icon to yours.'),
                    const SizedBox(height: 6),
                    infoButton(
                        'Design a Folder Icon for Desktop with flat white background:\nColor: Dark Gray\nText: Settings\nIcon: Settings Gear\n'
                        'Design: Modern with just a few details, folder slighly opened to the left, text below the icon inside the folder, folder color has a slighly gradient, square aspect ratio',
                        selectable: true),
                    const SizedBox(height: 6),
                    infoButton(
                        'ChatGPT Image Generator has transparent Background, others do not support, so specify white background for non ChatGPT'),
                  ],
                ),
              ),
            ),
          ]),
        ));
  }

  Container infoButton(String info, {bool selectable = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: Design.accent.withAlpha(180)),
          const SizedBox(width: 8),
          Expanded(
            child: !selectable
                ? Text(info,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 2,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
                        height: 1.5))
                : SelectableText(info,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 2,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
                        height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ── remove.bg API ──────────────────────────────────────────────────────────────

class _RemoveBgException implements Exception {
  const _RemoveBgException(this.message);
  final String message;
}

Future<Uint8List> _callRemoveBgApi({
  required String imagePath,
  required String apiKey,
}) async {
  final Uri uri = Uri.parse('https://api.remove.bg/v1.0/removebg');

  final http.MultipartRequest request = http.MultipartRequest('POST', uri)
    ..headers['X-Api-Key'] = apiKey
    ..fields['size'] = 'auto'
    ..files.add(await http.MultipartFile.fromPath('image_file', imagePath));

  final http.StreamedResponse streamed = await request.send().timeout(const Duration(seconds: 60));
  final Uint8List bodyBytes = await streamed.stream.toBytes();

  if (streamed.statusCode == 200) {
    return bodyBytes;
  }

  // Try to parse error JSON
  String errorMessage = 'remove.bg returned status ${streamed.statusCode}.';
  try {
    final Map<String, dynamic> json = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
    final List<dynamic>? errors = json['errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      final String title = (errors.first as Map<String, dynamic>)['title'] as String? ?? errorMessage;
      errorMessage = 'remove.bg: $title';
    }
  } catch (_) {}

  if (streamed.statusCode == 402) {
    errorMessage = 'remove.bg: No credits remaining. Top up at remove.bg.';
  } else if (streamed.statusCode == 403) {
    errorMessage = 'remove.bg: Invalid API key.';
  }

  throw _RemoveBgException(errorMessage);
}

// ── Helper: write desktop.ini ──────────────────────────────────────────────────

Future<void> _applyDesktopIni(String folderPath, String icoPath) async {
  await Process.run('attrib', <String>['+s', folderPath]);

  final File iniFile = File('$folderPath\\desktop.ini');

  if (await iniFile.exists()) {
    await Process.run('attrib', <String>['-h', '-s', iniFile.path]);
  }
  final String content = '[.ShellClassInfo]\r\nIconResource=$icoPath,0\r\n';
  await iniFile.writeAsString(content, flush: true);

  await Process.run('attrib', <String>['+h', '+s', iniFile.path]);
}

// ── Isolate worker ─────────────────────────────────────────────────────────────

String _processAndSaveIcon(Map<String, String> args) {
  final String imagePath = args['imagePath']!;
  final String cacheDir = args['cacheDir']!;

  final File sourceFile = File(imagePath);
  if (!sourceFile.existsSync()) throw Exception('Image file not found: $imagePath');

  final img.Image? decoded = img.decodeImage(sourceFile.readAsBytesSync());
  if (decoded == null) throw Exception('Could not decode image.');

  final img.Image cropped = _autoCrop(decoded);
  final img.Image resized = _resizeCentered(cropped, 256);
  final List<int> icoBytes = img.encodeIco(resized);

  final Directory dir = Directory(cacheDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final String icoPath = '$cacheDir\\${_randomId()}.ico';
  File(icoPath).writeAsBytesSync(icoBytes, flush: true);

  return icoPath;
}

img.Image _autoCrop(img.Image src) {
  int left = src.width;
  int top = src.height;
  int right = 0;
  int bottom = 0;

  const int alphaThreshold = 10;

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final img.Pixel pixel = src.getPixel(x, y);
      if (pixel.a.toInt() > alphaThreshold) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }

  if (left >= right || top >= bottom) return src;
  return img.copyCrop(src, x: left, y: top, width: right - left + 1, height: bottom - top + 1);
}

img.Image _resizeCentered(img.Image src, int size) {
  final double scale = size / (src.width > src.height ? src.width : src.height);
  final int newW = (src.width * scale).round().clamp(1, size);
  final int newH = (src.height * scale).round().clamp(1, size);

  final img.Image scaled = img.copyResize(src, width: newW, height: newH, interpolation: img.Interpolation.average);

  final img.Image canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(canvas, scaled, dstX: (size - newW) ~/ 2, dstY: (size - newH) ~/ 2);
  return canvas;
}

String _randomId() {
  const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final Random rng = Random();
  return List<String>.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
}

// ── Reusable sub-widgets ───────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.label,
    required this.accent,
    required this.onSurface,
    required this.child,
  });

  final int step;
  final String label;
  final Color accent;
  final Color onSurface;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '$step',
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 2,
                      fontWeight: FontWeight.w600,
                      color: onSurface)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final IconData icon;
  final String? value;
  final String placeholder;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withAlpha(12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withAlpha(30)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value ?? placeholder,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: value != null ? onSurface : onSurface.withAlpha(100)),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 16, color: onSurface.withAlpha(120)),
          ],
        ),
      ),
    );
  }
}

class RemoveBgBalance {
  final double totalCredits;
  final double subscriptionCredits;
  final double payAsYouGoCredits;
  final double enterpriseCredits;
  final int freePreviewsLeft;

  RemoveBgBalance({
    required this.totalCredits,
    required this.subscriptionCredits,
    required this.payAsYouGoCredits,
    required this.enterpriseCredits,
    required this.freePreviewsLeft,
  });

  factory RemoveBgBalance.fromJson(Map<String, dynamic> attributes) {
    // ignore: always_specify_types
    final credits = attributes['credits'] ?? <dynamic, dynamic>{};
    return RemoveBgBalance(
      totalCredits: (credits['total'] ?? 0.0).toDouble(),
      subscriptionCredits: (credits['subscription'] ?? 0.0).toDouble(),
      payAsYouGoCredits: (credits['pay_as_you_go'] ?? 0.0).toDouble(),
      enterpriseCredits: (credits['enterprise'] ?? 0.0).toDouble(),
      // 'free_calls' represents your remaining free preview API calls
      freePreviewsLeft: attributes['api']?['free_calls'] ?? 0,
    );
  }
  int get credits => totalCredits.toInt() + freePreviewsLeft;
  @override
  String toString() {
    return 'RemoveBgBalance(totalCredits: $totalCredits, subscriptionCredits: $subscriptionCredits, payAsYouGoCredits: $payAsYouGoCredits, enterpriseCredits: $enterpriseCredits, freePreviewsLeft: $freePreviewsLeft)';
  }
}
