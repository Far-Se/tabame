import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class WallpapersButton extends StatelessWidget {
  const WallpapersButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Wallpapers", icon: const Icon(Icons.photo_library_outlined), child: () => const WallpapersPanel());
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

  WallpaperFillMode _fillMode = WallpaperFillMode.fill;
  int _monitorCount = 1;

  @override
  void initState() {
    super.initState();
    _monitorCount = Monitor.list.length;
    _folderPath = (widget.initialFolderPath?.trim().isNotEmpty ?? false)
        ? widget.initialFolderPath!.trim()
        : userSettings.wallpapersFolder;
    _currentWallpaperPath = WinUtils.getDesktopBackgroundType() == DesktopBackgroundType.wallpaper
        ? WinUtils.getDesktopWallpaperPath()
        : null;
    _refreshImages();
  }

  void _cycleFillMode() {
    setState(() {
      final int nextIndex = (_fillMode.index + 1) % WallpaperFillMode.values.length;
      _fillMode = WallpaperFillMode.values[nextIndex];
    });
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
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select wallpapers folder';
    final Directory? dir = dirPicker.getDirectory();

    Timer(const Duration(milliseconds: 1000), () async {
      QuickMenuFunctions.keepOpen = false;
    });
    if (dir == null || dir.path.isEmpty) return;

    _folderPath = dir.path;
    if (widget.saveSelectionToSettings) {
      userSettings.wallpapersFolder = dir.path;
      await Boxes.updateSettings("wallpapersFolder", dir.path);
    }
    _refreshImages();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final bool folderExists = _folderPath.trim().isNotEmpty && Directory(_folderPath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: widget.title,
          accent: accent,
          icon: Icons.wallpaper_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: <Widget>[
              CustomTooltip(
                message: "Fill Mode: ${_fillMode.name.toUpperCase()}",
                child: TextButton.icon(
                  onPressed: _cycleFillMode,
                  icon: Icon(_getFillModeIcon(_fillMode), size: 16),
                  label: Text(_fillMode.name.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    backgroundColor: accent.withAlpha(20),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                          monitorCount: _monitorCount,
                          onSet: (int monitor) {
                            WinUtils.setWallpaper(image, monitor, _fillMode);
                            setState(() {
                              _currentWallpaperPath = image.path;
                            });
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  IconData _getFillModeIcon(WallpaperFillMode mode) {
    switch (mode) {
      case WallpaperFillMode.center:
        return Icons.center_focus_strong_rounded;
      case WallpaperFillMode.tile:
        return Icons.grid_view_rounded;
      case WallpaperFillMode.stretch:
        return Icons.unfold_more_rounded;
      case WallpaperFillMode.fit:
        return Icons.fit_screen_rounded;
      case WallpaperFillMode.fill:
        return Icons.crop_free_rounded;
      case WallpaperFillMode.span:
        return Icons.view_sidebar_rounded;
    }
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
    required this.monitorCount,
    required this.onSet,
  });

  final File image;
  final Color accent;
  final bool isCurrent;
  final int monitorCount;
  final Function(int) onSet;

  @override
  State<_WallpaperRow> createState() => _WallpaperRowState();
}

class _WallpaperRowState extends State<_WallpaperRow> {
  bool _hovered = false;
  late Future<File?> _thumbnailFuture;
  OverlayEntry? _previewEntry;
  int _selectedMonitor = 0;

  @override
  void dispose() {
    _hidePreview();
    super.dispose();
  }

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

  Future<File?> _getThumbnailFuture() {
    return _WallpaperThumbnailQueue.instance.getThumbnail(widget.image.path);
  }

  void _showMonitorPicker(BuildContext context) {
    showQuickMenuModal(
      context: context,
      heightFactor: 0.8,
      child: Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.monitor_rounded, size: 18, color: userSettings.themeColors.accent),
                const SizedBox(width: 8),
                const Text(
                  "Select Display",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _MonitorLayoutPicker(
                accent: userSettings.themeColors.accent,
                onSelect: (int monitorIndex) {
                  setState(() => _selectedMonitor = monitorIndex);
                  Navigator.of(context).pop();
                  widget.onSet(monitorIndex);
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Click a monitor to apply wallpaper",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context) {
    if (_previewEntry != null) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // Position next to the thumbnail (8px padding + 64px thumb width)
    const double thumbRelativeRight = 8 + 64;
    final double thumbRightGlobal = offset.dx + thumbRelativeRight;

    // Remaining width in the popup/row (minus gaps and padding)
    final double availableWidth = (size.width - thumbRelativeRight - 24).clamp(100.0, 300.0);
    final double calculatedHeight = availableWidth * 0.625; // Maintain ~1.6 ratio

    _previewEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: thumbRightGlobal + 12,
        top: offset.dy - 30,
        child: Material(
          elevation: 12,
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: availableWidth,
            height: calculatedHeight,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withAlpha(30)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.file(
                  widget.image,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[
                          Colors.black.withAlpha(180),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      widget.image.path.split('\\').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_previewEntry!);
  }

  void _hidePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
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
          color: _hovered ? userSettings.themeColors.accent.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isCurrent ? userSettings.themeColors.accent.withAlpha(150) : onSurface.withAlpha(18),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSet(_selectedMonitor),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                MouseRegion(
                  onEnter: (_) => _showPreview(context),
                  onExit: (_) => _hidePreview(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FutureBuilder<File?>(
                      future: _thumbnailFuture,
                      builder: (BuildContext context, AsyncSnapshot<File?> snap) {
                        final File? bytes = snap.data;
                        if (bytes != null) {
                          return Image.file(
                            bytes,
                            width: 64,
                            height: 40,
                            cacheWidth: 64,
                            cacheHeight: 40,
                            gaplessPlayback: true,
                            fit: BoxFit.cover,
                          );
                        }

                        return Container(
                          width: 64,
                          height: 40,
                          color: userSettings.themeColors.accent.withAlpha(20),
                          alignment: Alignment.center,
                          child: Icon(
                            snap.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
                            size: 16,
                            color: userSettings.themeColors.accent.withAlpha(180),
                          ),
                        );
                      },
                    ),
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
                          color: widget.isCurrent
                              ? userSettings.themeColors.accent.withAlpha(220)
                              : onSurface.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.monitorCount > 1) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showMonitorPicker(context),
                    icon: Icon(Icons.monitor_rounded, size: 16, color: onSurface.withAlpha(150)),
                    tooltip: "Select Monitor",
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      backgroundColor: onSurface.withAlpha(10),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  widget.isCurrent ? Icons.check_circle_rounded : Icons.wallpaper_rounded,
                  size: 16,
                  color: widget.isCurrent ? userSettings.themeColors.accent : onSurface.withAlpha(_hovered ? 180 : 120),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonitorLayoutPicker extends StatelessWidget {
  const _MonitorLayoutPicker({
    required this.accent,
    required this.onSelect,
  });

  final Color accent;
  final Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final List<int> monitorList = Monitor.list;
    if (monitorList.isEmpty) return const SizedBox.shrink();

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    final Map<int, Square> sizes = Monitor.monitorSizes;
    for (final int handle in monitorList) {
      final Square size = sizes[handle]!;
      if (size.x < minX) minX = size.x.toDouble();
      if (size.y < minY) minY = size.y.toDouble();
      if (size.x + size.width > maxX) maxX = (size.x + size.width).toDouble();
      if (size.y + size.height > maxY) maxY = (size.y + size.height).toDouble();
    }

    final double totalWidth = maxX - minX;
    final double totalHeight = maxY - minY;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scaleX = constraints.maxWidth / totalWidth;
        final double scaleY = constraints.maxHeight / totalHeight;
        final double scale = (scaleX < scaleY ? scaleX : scaleY) * 0.9;

        final double offsetX = (constraints.maxWidth - totalWidth * scale) / 2;
        final double offsetY = (constraints.maxHeight - totalHeight * scale) / 2;

        return Stack(
          children: <Widget>[
            for (int i = 0; i < monitorList.length; i++) ...<Widget>[
              (() {
                final int handle = monitorList[i];
                final Square size = sizes[handle]!;
                final double left = (size.x - minX) * scale + offsetX;
                final double top = (size.y - minY) * scale + offsetY;
                final double width = size.width * scale;
                final double height = size.height * scale;

                return Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: _MonitorItem(
                    index: i,
                    accent: accent,
                    onTap: () => onSelect(i),
                  ),
                );
              })(),
            ],
          ],
        );
      },
    );
  }
}

class _MonitorItem extends StatefulWidget {
  const _MonitorItem({
    required this.index,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_MonitorItem> createState() => _MonitorItemState();
}

class _MonitorItemState extends State<_MonitorItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _hovered ? userSettings.themeColors.accent.withAlpha(40) : onSurface.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? userSettings.themeColors.accent : onSurface.withAlpha(50),
              width: _hovered ? 2 : 1,
            ),
            boxShadow: _hovered
                ? <BoxShadow>[
                    BoxShadow(
                      color: userSettings.themeColors.accent.withAlpha(40),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.monitor_rounded,
                size: 20,
                color: _hovered ? userSettings.themeColors.accent : onSurface.withAlpha(180),
              ),
              const SizedBox(height: 4),
              Text(
                "${widget.index + 1}",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _hovered ? userSettings.themeColors.accent : onSurface.withAlpha(180),
                ),
              ),
            ],
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
  static const String _thumbnailFolderName = r'cache\wallpaper thumb';

  final Set<String> _inFlight = <String>{};
  final List<String> _queue = <String>[];
  bool _isProcessing = false;

  Future<File?> getThumbnail(String imagePath) async {
    final File? persisted = await _readPersistedThumbnailIfFresh(imagePath);
    if (persisted != null) {
      return persisted;
    }

    if (!_inFlight.contains(imagePath) && !_queue.contains(imagePath)) {
      _queue.add(imagePath);
      _pumpQueue();
    }

    return File(imagePath);
  }

  void primeQueue(List<File> images) {
    for (final File image in images) {
      if (_inFlight.contains(image.path) || _queue.contains(image.path)) {
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
      _inFlight.add(imagePath);

      try {
        File? thumbFile = await _readPersistedThumbnailIfFresh(imagePath);
        if (thumbFile == null) {
          final Uint8List? bytes = await compute<Map<String, Object>, Uint8List?>(
            _generateWallpaperThumbnail,
            <String, Object>{
              'path': imagePath,
              'width': _thumbnailWidth,
              'height': _thumbnailHeight,
            },
          );

          if (bytes != null && bytes.isNotEmpty) {
            final String thumbPath = _thumbnailPathFor(imagePath);
            thumbFile = File(thumbPath);
            await thumbFile.writeAsBytes(bytes, flush: true);
          }
        }
      } catch (_) {
        // Silently fail
      } finally {
        _inFlight.remove(imagePath);
      }
    }

    _isProcessing = false;
  }

  Future<File?> _readPersistedThumbnailIfFresh(String imagePath) async {
    try {
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
      return thumbFile;
    } catch (_) {
      return null;
    }
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
