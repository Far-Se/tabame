import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class WallpapersButton extends StatelessWidget {
  const WallpapersButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Wallpapers",
      icon: const Icon(Icons.photo_library_outlined),
      onTap: () {
        openWallpapersPicker(context);
      },
    );
  }
}

class WallpapersQuickAction extends StatelessWidget {
  const WallpapersQuickAction({
    super.key,
    required this.title,
    required this.folderPath,
  });

  final String title;
  final String folderPath;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openWallpapersPicker(
        context,
        title: title,
        folderPath: folderPath,
        saveSelectionToSettings: folderPath.trim().isEmpty,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 5),
            const SizedBox(
              width: 20,
              child: Icon(Icons.photo_library_outlined, size: 16),
            ),
            const SizedBox(width: 5),
            Expanded(child: Text(title)),
          ],
        ),
      ),
    );
  }
}

Future<void> openWallpapersPicker(
  BuildContext context, {
  String title = "Wallpapers",
  String? folderPath,
  bool saveSelectionToSettings = true,
}) async {
  await showQuickMenuModal(
    context: context,
    child: WallpapersPanel(
      title: title,
      initialFolderPath: folderPath,
      saveSelectionToSettings: saveSelectionToSettings,
    ),
  );
}

class WallpapersPanel extends StatefulWidget {
  const WallpapersPanel({
    super.key,
    this.title = "Wallpapers",
    this.initialFolderPath,
    this.saveSelectionToSettings = true,
  });

  final String title;
  final String? initialFolderPath;
  final bool saveSelectionToSettings;

  @override
  State<WallpapersPanel> createState() => _WallpapersPanelState();
}

class _WallpapersPanelState extends State<WallpapersPanel> {
  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.gif',
    '.webp',
  };

  late String _folderPath;
  List<File> _images = <File>[];
  String? _currentWallpaperPath;
  final _WallpaperThumbnailQueue _thumbnailQueue = _WallpaperThumbnailQueue.instance;

  @override
  void initState() {
    super.initState();
    _folderPath = (widget.initialFolderPath?.trim().isNotEmpty ?? false)
        ? widget.initialFolderPath!.trim()
        : globalSettings.wallpapersFolder;
    _currentWallpaperPath = WinUtils.getDesktopBackgroundType() == DesktopBackgroundType.wallpaper
        ? WinUtils.getDesktopWallpaperPath()
        : null;
    _refreshImages();
  }

  void _refreshImages() {
    final String folderPath = _folderPath.trim();
    final Directory directory = Directory(folderPath);

    if (folderPath.isEmpty || !directory.existsSync()) {
      setState(() {
        _images = <File>[];
      });
      return;
    }

    final List<File> images = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((File file) => _imageExtensions.contains(_extension(file.path)))
        .toList()
      ..sort((File a, File b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    _thumbnailQueue.primeQueue(images);

    setState(() {
      _images = images;
    });
  }

  String _extension(String path) {
    final int index = path.lastIndexOf('.');
    if (index == -1) return '';
    return path.substring(index).toLowerCase();
  }

  Future<void> _pickFolder() async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select wallpapers folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;

    _folderPath = dir.path;
    if (widget.saveSelectionToSettings) {
      globalSettings.wallpapersFolder = dir.path;
      await Boxes.updateSettings("wallpapersFolder", dir.path);
    }
    _refreshImages();
  }

  Future<void> _setWallpaper(File file) async {
    final bool ok = WinUtils.setDesktopWallpaper(file.path);
    if (!ok || !mounted) return;
    setState(() {
      _currentWallpaperPath = file.path;
    });
    // Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final bool folderExists = _folderPath.trim().isNotEmpty && Directory(_folderPath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: widget.title,
          accent: accent,
          boldFont: globalSettings.theme.quickMenuBoldFont,
          icon: Icons.wallpaper_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _folderPath.trim().isEmpty ? "No folder selected" : _folderPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(190),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: TextButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text("Pick"),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: !folderExists
              ? const _WallpapersHint(
                  icon: Icons.folder_open_rounded,
                  message: "Pick a folder with images to start.",
                )
              : _images.isEmpty
                  ? const _WallpapersHint(
                      icon: Icons.image_not_supported_outlined,
                      message: "No supported images found in this folder.",
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: _images.length,
                      itemBuilder: (BuildContext context, int index) {
                        final File image = _images[index];
                        final bool isCurrent = _currentWallpaperPath?.toLowerCase() == image.path.toLowerCase();
                        return _WallpaperRow(
                          image: image,
                          accent: accent,
                          isCurrent: isCurrent,
                          onTap: () => _setWallpaper(image),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _WallpapersHint extends StatelessWidget {
  const _WallpapersHint({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.onSurface.withAlpha(110)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(170),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperRow extends StatefulWidget {
  const _WallpaperRow({
    required this.image,
    required this.accent,
    required this.isCurrent,
    required this.onTap,
  });

  final File image;
  final Color accent;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_WallpaperRow> createState() => _WallpaperRowState();
}

class _WallpaperRowState extends State<_WallpaperRow> {
  bool _hovered = false;
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _getThumbnailFuture();
  }

  @override
  void didUpdateWidget(covariant _WallpaperRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path) {
      _thumbnailFuture = _getThumbnailFuture();
    }
  }

  Future<Uint8List?> _getThumbnailFuture() {
    return _WallpaperThumbnailQueue.instance.getThumbnail(widget.image.path);
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final String name = widget.image.path.split('\\').last;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isCurrent ? widget.accent.withAlpha(150) : onSurface.withAlpha(18),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbnailFuture,
                    builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
                      final Uint8List? bytes = snap.data;
                      if (bytes != null && bytes.isNotEmpty) {
                        return Image.memory(
                          bytes,
                          width: 64,
                          height: 40,
                          gaplessPlayback: true,
                          fit: BoxFit.cover,
                        );
                      }

                      return Container(
                        width: 64,
                        height: 40,
                        color: widget.accent.withAlpha(20),
                        alignment: Alignment.center,
                        child: Icon(
                          snap.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
                          size: 16,
                          color: widget.accent.withAlpha(180),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isCurrent ? "Current wallpaper" : "Set as wallpaper",
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isCurrent ? widget.accent.withAlpha(220) : onSurface.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  widget.isCurrent ? Icons.check_circle_rounded : Icons.wallpaper_rounded,
                  size: 16,
                  color: widget.isCurrent ? widget.accent : onSurface.withAlpha(_hovered ? 180 : 120),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperThumbnailQueue {
  _WallpaperThumbnailQueue._();

  static final _WallpaperThumbnailQueue instance = _WallpaperThumbnailQueue._();

  static const int _thumbnailWidth = 64;
  static const int _thumbnailHeight = 40;
  static const String _thumbnailFolderName = 'wallpaper thumb';

  final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  final Map<String, Completer<Uint8List?>> _inFlight = <String, Completer<Uint8List?>>{};
  final List<String> _queue = <String>[];
  bool _isProcessing = false;

  Future<Uint8List?> getThumbnail(String imagePath) async {
    final Uint8List? cached = _memoryCache[imagePath];
    if (cached != null) return cached;

    final Uint8List? persisted = await _readPersistedThumbnailIfFresh(imagePath);
    if (persisted != null) {
      _memoryCache[imagePath] = persisted;
      return persisted;
    }

    final Completer<Uint8List?>? current = _inFlight[imagePath];
    if (current != null) return current.future;

    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    _inFlight[imagePath] = completer;
    if (!_queue.contains(imagePath)) {
      _queue.add(imagePath);
    }
    _pumpQueue();
    return completer.future;
  }

  void primeQueue(List<File> images) {
    for (final File image in images) {
      if (_memoryCache.containsKey(image.path) || _inFlight.containsKey(image.path) || _queue.contains(image.path)) {
        continue;
      }
      _queue.add(image.path);
    }
    _pumpQueue();
  }

  Future<void> _pumpQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final String imagePath = _queue.removeAt(0);
      final Completer<Uint8List?>? completer = _inFlight[imagePath];

      try {
        Uint8List? bytes = await _readPersistedThumbnailIfFresh(imagePath);
        if (bytes == null) {
          bytes = await compute<Map<String, Object>, Uint8List?>(
            _generateWallpaperThumbnail,
            <String, Object>{
              'path': imagePath,
              'width': _thumbnailWidth,
              'height': _thumbnailHeight,
            },
          );

          if (bytes != null && bytes.isNotEmpty) {
            await File(_thumbnailPathFor(imagePath)).writeAsBytes(bytes, flush: true);
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          _memoryCache[imagePath] = bytes;
        }

        completer?.complete(bytes);
      } catch (_) {
        completer?.complete(null);
      } finally {
        _inFlight.remove(imagePath);
      }
    }

    _isProcessing = false;
  }

  Future<Uint8List?> _readPersistedThumbnailIfFresh(String imagePath) async {
    final File imageFile = File(imagePath);
    final File thumbFile = File(_thumbnailPathFor(imagePath));

    if (!await imageFile.exists() || !await thumbFile.exists()) {
      return null;
    }

    final DateTime imageModified = await imageFile.lastModified();
    final DateTime thumbModified = await thumbFile.lastModified();
    if (thumbModified.isBefore(imageModified)) {
      return null;
    }

    final Uint8List bytes = await thumbFile.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  String _thumbnailPathFor(String imagePath) {
    final Directory thumbnailDirectory = Directory(
      '${WinUtils.getTabameAppDataFolder()}\\$_thumbnailFolderName',
    );
    if (!thumbnailDirectory.existsSync()) {
      thumbnailDirectory.createSync(recursive: true);
    }

    final String fileName = imagePath.split(RegExp(r'[\\/]')).last;
    return '${thumbnailDirectory.path}\\$fileName.thumb';
  }
}

Uint8List? _generateWallpaperThumbnail(Map<String, Object> args) {
  final String path = args['path']! as String;
  final int width = args['width']! as int;
  final int height = args['height']! as int;

  final File file = File(path);
  if (!file.existsSync()) return null;

  final Uint8List sourceBytes = file.readAsBytesSync();
  final img.Image? decoded = img.decodeImage(sourceBytes);
  if (decoded == null) return null;

  final img.Image thumbnail = img.copyResizeCropSquare(
    decoded,
    size: width > height ? width : height,
  );
  final img.Image fitted = img.copyResize(
    thumbnail,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );

  final List<int> encoded = img.encodeJpg(fitted, quality: 82);
  return Uint8List.fromList(encoded);
}
