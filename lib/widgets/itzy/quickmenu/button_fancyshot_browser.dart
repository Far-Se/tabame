import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

// ─────────────────────────────────────────────
//  Button
// ─────────────────────────────────────────────

class FancyShotBrowserButton extends StatelessWidget {
  const FancyShotBrowserButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "FancyShot Browser",
      icon: const Icon(Icons.photo_camera_outlined),
      child: () => const FancyShotBrowserPanel(),
    );
  }
}

// ─────────────────────────────────────────────
//  Panel
// ─────────────────────────────────────────────

enum _MediaType { screenshots, recordings }

class FancyShotBrowserPanel extends StatefulWidget {
  const FancyShotBrowserPanel({super.key});

  @override
  State<FancyShotBrowserPanel> createState() => _FancyShotBrowserPanelState();
}

class _FancyShotBrowserPanelState extends State<FancyShotBrowserPanel> {
  static const Set<String> _imageExtensions = <String>{'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp'};
  static const Set<String> _videoExtensions = <String>{'.mp4', '.mkv', '.avi', '.mov', '.webm', '.gif'};

  _MediaType _mediaType = _MediaType.screenshots;

  /// null = month list view; non-null = files view for that month folder
  String? _selectedMonthFolder;

  List<Directory> _monthFolders = <Directory>[];
  List<File> _files = <File>[];

  // ── Lifecycle ─────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadMonths();
  }

  // ── Helpers ───────────────────────────────

  String get _rootFolder => _mediaType == _MediaType.screenshots
      ? '${WinUtils.getTabameAppDataFolder()}\\screenshots'
      : '${WinUtils.getTabameAppDataFolder()}\\recordings';

  bool _isMediaFile(String path) {
    final String ext = _extension(path);
    return _mediaType == _MediaType.screenshots ? _imageExtensions.contains(ext) : _videoExtensions.contains(ext);
  }

  String _extension(String path) {
    final int i = path.lastIndexOf('.');
    return i == -1 ? '' : path.substring(i).toLowerCase();
  }

  void _loadMonths() {
    final Directory root = Directory(_rootFolder);
    if (!root.existsSync()) {
      setState(() {
        _monthFolders = <Directory>[];
        _selectedMonthFolder = null;
      });
      return;
    }

    final List<Directory> dirs = root.listSync(followLinks: false).whereType<Directory>().toList()
      ..sort((Directory a, Directory b) {
        // Sort newest first by folder name ("2026 - May")
        return b.path.toLowerCase().compareTo(a.path.toLowerCase());
      });

    setState(() {
      _monthFolders = dirs;
      _selectedMonthFolder = null;
      _files = <File>[];
    });
  }

  void _loadFiles(String monthFolderPath) {
    final Directory dir = Directory(monthFolderPath);
    if (!dir.existsSync()) {
      setState(() {
        _files = <File>[];
        _selectedMonthFolder = monthFolderPath;
      });
      return;
    }

    final List<File> files = dir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((File f) => _isMediaFile(f.path))
        .toList()
      ..sort((File a, File b) => b.statSync().changed.compareTo(a.statSync().changed));

    setState(() {
      _selectedMonthFolder = monthFolderPath;
      _files = files;
    });
  }

  void _switchMediaType(_MediaType type) {
    if (_mediaType == type) return;
    setState(() {
      _mediaType = type;
      _selectedMonthFolder = null;
      _files = <File>[];
    });
    _loadMonths();
  }

  String _folderLabel(Directory dir) {
    return dir.path.split(RegExp(r'[\\/]')).last;
  }

  int _fileCount(Directory dir) {
    try {
      return dir.listSync(followLinks: false).whereType<File>().where((File f) => _isMediaFile(f.path)).length;
    } catch (_) {
      return 0;
    }
  }

  // ── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header ──
        PanelHeader(
            title:
                _selectedMonthFolder != null ? _selectedMonthFolder!.split(RegExp(r'[\\/]')).last : 'FancyShot Browser',
            accent: accent,
            icon: _mediaType == _MediaType.screenshots ? Icons.photo_camera_outlined : Icons.videocam_outlined,
            extraActions: _selectedMonthFolder != null
                ? <Widget>[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      tooltip: 'Back',
                      onPressed: _loadMonths,
                      splashRadius: 18,
                    )
                  ]
                : null),

        // ── Screenshots / Recordings toggle ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: <Widget>[
              _TypeButton(
                label: 'Screenshots',
                icon: Icons.photo_camera_outlined,
                active: _mediaType == _MediaType.screenshots,
                accent: accent,
                onTap: () => _switchMediaType(_MediaType.screenshots),
              ),
              const SizedBox(width: 8),
              _TypeButton(
                label: 'Recordings',
                icon: Icons.videocam_outlined,
                active: _mediaType == _MediaType.recordings,
                accent: accent,
                onTap: () => _switchMediaType(_MediaType.recordings),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // ── Content ──
        Flexible(
          child: _selectedMonthFolder == null ? _buildMonthList(accent, onSurface) : _buildFileGrid(accent, onSurface),
        ),
      ],
    );
  }

  // ── Month list ────────────────────────────

  Widget _buildMonthList(Color accent, Color onSurface) {
    if (_monthFolders.isEmpty) {
      return _Hint(
        icon: _mediaType == _MediaType.screenshots ? Icons.photo_camera_outlined : Icons.videocam_outlined,
        message: 'No ${_mediaType == _MediaType.screenshots ? 'screenshot' : 'recording'} folders found.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      itemCount: _monthFolders.length,
      itemBuilder: (BuildContext context, int index) {
        final Directory dir = _monthFolders[index];
        final String label = _folderLabel(dir);
        final int count = _fileCount(dir);
        return _MonthRow(
          label: label,
          count: count,
          accent: accent,
          onSurface: onSurface,
          onTap: () => _loadFiles(dir.path),
        );
      },
    );
  }

  // ── File grid ─────────────────────────────

  Widget _buildFileGrid(Color accent, Color onSurface) {
    if (_files.isEmpty) {
      return const _Hint(
        icon: Icons.image_not_supported_outlined,
        message: 'No files found in this folder.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.6,
      ),
      itemCount: _files.length,
      itemBuilder: (BuildContext context, int index) {
        return _MediaTile(
          file: _files[index],
          accent: accent,
          onSurface: onSurface,
          isVideo: _mediaType == _MediaType.recordings,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────

/// Toggle button for Screenshots / Recordings
class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          backgroundColor: active ? accent.withAlpha(30) : accent.withAlpha(8),
          foregroundColor: active ? accent : Theme.of(context).colorScheme.onSurface.withAlpha(160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          minimumSize: const Size(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: active ? BorderSide(color: accent.withAlpha(80), width: 1) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Month folder row
class _MonthRow extends StatefulWidget {
  const _MonthRow({
    required this.label,
    required this.count,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  State<_MonthRow> createState() => _MonthRowState();
}

class _MonthRowState extends State<_MonthRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  width: _hovered ? 2.5 : 0,
                  height: 16,
                  margin: EdgeInsets.only(right: _hovered ? 8 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  Icons.folder_outlined,
                  size: 16,
                  color: _hovered ? widget.accent : widget.onSurface.withAlpha(160),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(210),
                    ),
                  ),
                ),
                if (widget.count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.accent.withAlpha(_hovered ? 40 : 18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.accent,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: widget.onSurface.withAlpha(_hovered ? 180 : 80),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single media tile in the grid
class _MediaTile extends StatefulWidget {
  const _MediaTile({
    required this.file,
    required this.accent,
    required this.onSurface,
    required this.isVideo,
  });

  final File file;
  final Color accent;
  final Color onSurface;
  final bool isVideo;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  bool _hovered = false;

  String get _fileName => widget.file.path.split(RegExp(r'[\\/]')).last;

  Future<void> _copyImage() async {
    try {
      final Uint8List bytes = await widget.file.readAsBytes();
      await ClipboardExtended.copyImage(bytes);
    } catch (_) {}
  }

  void _copyFilePath() {
    ClipboardExtension.copyFile(widget.file.path);
  }

  void _openFile() {
    // Open with default OS handler
    Process.run('explorer', <String>[widget.file.path]);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hovered ? widget.accent.withAlpha(160) : widget.onSurface.withAlpha(30),
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: _hovered
              ? <BoxShadow>[
                  BoxShadow(
                    color: widget.accent.withAlpha(25),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Thumbnail
            widget.isVideo
                ? _VideoThumb(file: widget.file, onSurface: widget.onSurface)
                : _ImageThumb(file: widget.file),

            // Overlay on hover
            if (_hovered)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 130),
                opacity: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withAlpha(0),
                        Colors.black.withAlpha(180),
                      ],
                    ),
                  ),
                ),
              ),

            // Action buttons (bottom strip on hover)
            if (_hovered)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      if (!widget.isVideo)
                        _TileActionButton(
                          icon: Icons.image_outlined,
                          tooltip: 'Copy image',
                          accent: widget.accent,
                          onTap: _copyImage,
                        ),
                      _TileActionButton(
                        icon: Icons.copy_outlined,
                        tooltip: 'Copy file',
                        accent: widget.accent,
                        onTap: _copyFilePath,
                      ),
                      _TileActionButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip: 'Open',
                        accent: widget.accent,
                        onTap: _openFile,
                      ),
                    ],
                  ),
                ),
              ),

            // Filename chip (top, always visible on hover)
            if (_hovered)
              Positioned(
                left: 4,
                right: 4,
                top: 4,
                child: Text(
                  _fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TileActionButton extends StatelessWidget {
  const _TileActionButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });

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
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(120),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: Colors.white),
        ),
      ),
    );
  }
}

/// Image thumbnail using Flutter's Image.file with memory constraints
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: 300,
      errorBuilder: (_, __, ___) => const _ThumbError(),
    );
  }
}

/// Video thumbnail placeholder (video frames require a video plugin; show icon for now)
class _VideoThumb extends StatelessWidget {
  const _VideoThumb({required this.file, required this.onSurface});
  final File file;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: onSurface.withAlpha(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.videocam_outlined, size: 22, color: onSurface.withAlpha(120)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              file.path.split(RegExp(r'[\\/]')).last,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: onSurface.withAlpha(160)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbError extends StatelessWidget {
  const _ThumbError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.onSurface.withAlpha(10),
      child: Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.message});
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
