import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../platform/file_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../models/settings.dart';
import 'image_split.dart';

enum _ImageTool {
  centerImages,
  imageSplit,
}

enum _CenterImageAspectPreset {
  tight,
  square,
  rectangle,
  portrait,
  wide,
  custom,
}

class _CenterImageJob {
  const _CenterImageJob({required this.bytes, required this.aspectRatio});

  final Uint8List bytes;
  final double? aspectRatio;
}

class _CenterImageAnalysis {
  const _CenterImageAnalysis({
    required this.sourceBytes,
    required this.outputBytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.outputContentLeft,
    required this.outputContentTop,
    required this.hasVisiblePixels,
    required this.hasTransparentMargin,
    this.error,
  });

  final Uint8List sourceBytes;
  final Uint8List outputBytes;
  final int sourceWidth;
  final int sourceHeight;
  final int outputWidth;
  final int outputHeight;
  final int cropLeft;
  final int cropTop;
  final int cropWidth;
  final int cropHeight;
  final int outputContentLeft;
  final int outputContentTop;
  final bool hasVisiblePixels;
  final bool hasTransparentMargin;
  final String? error;
}

class _CenterImageEntry {
  _CenterImageEntry(this.file);

  final File file;
  _CenterImageAnalysis? analysis;
  bool isLoading = false;
  String? error;
}

/// Image utilities that can be extended with additional image tools later.
class ImageTools extends StatefulWidget {
  const ImageTools({super.key});

  @override
  State<ImageTools> createState() => _ImageToolsState();
}

class _ImageToolsState extends State<ImageTools> {
  static const int _alphaThreshold = 8;

  late final TextEditingController _customWidthController;
  late final TextEditingController _customHeightController;

  String _folderPath = '';
  List<_CenterImageEntry> _images = <_CenterImageEntry>[];
  int _selectedIndex = -1;
  _ImageTool _activeTool = _ImageTool.centerImages;
  _CenterImageAspectPreset _aspectPreset = _CenterImageAspectPreset.tight;

  bool _isLoadingFolder = false;
  bool _isProcessing = false;
  int _processedCount = 0;
  int _processingErrorCount = 0;
  String? _folderError;
  Timer? _customRatioDebounce;
  int _folderRequest = 0;
  int _previewRequest = 0;

  @override
  void initState() {
    super.initState();
    _customWidthController = TextEditingController(text: '4');
    _customHeightController = TextEditingController(text: '3');
    _folderPath = _folderFromArguments();
    if (_folderPath.isNotEmpty) _loadImages();
  }

  @override
  void dispose() {
    _customRatioDebounce?.cancel();
    _customWidthController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(accent, onSurface),
          const SizedBox(height: 10),
          Expanded(
            child: IndexedStack(
              index: _activeTool.index,
              children: <Widget>[
                _buildCenterImagesTool(accent, onSurface),
                const ImageSplitTool(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterImagesTool(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildFolderBar(accent, onSurface),
        const SizedBox(height: 10),
        _buildAspectBar(accent, onSurface),
        const SizedBox(height: 10),
        Expanded(child: _buildWorkspace(accent, onSurface)),
      ],
    );
  }

  Widget _buildHeader(Color accent, Color onSurface) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.auto_awesome_mosaic_rounded, color: accent, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Image Tools',
                style: TextStyle(
                  fontSize: Design.baseFontSize + 7,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.25,
                ),
              ),
              Text(
                _activeTool == _ImageTool.centerImages
                    ? 'Center transparent PNGs and normalize their canvas bounds.'
                    : 'Split one image into a precisely adjustable grid of files.',
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildToolSelector(accent, onSurface),
      ],
    );
  }

  Widget _buildToolSelector(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        border: Border.all(color: onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildToolTab(
            tool: _ImageTool.centerImages,
            label: 'CENTER IMAGES',
            icon: Icons.center_focus_strong_rounded,
            accent: accent,
            onSurface: onSurface,
          ),
          _buildToolTab(
            tool: _ImageTool.imageSplit,
            label: 'IMAGE SPLIT',
            icon: Icons.grid_view_rounded,
            accent: accent,
            onSurface: onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildToolTab({
    required _ImageTool tool,
    required String label,
    required IconData icon,
    required Color accent,
    required Color onSurface,
  }) {
    final bool selected = _activeTool == tool;
    return InkWell(
      onTap: () => setState(() => _activeTool = tool),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.13) : Colors.transparent,
          border: Border.all(color: selected ? accent.withValues(alpha: 0.48) : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: selected ? accent : onSurface.withValues(alpha: 0.55)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize - 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.45,
                color: selected ? accent : onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterAction(Color accent, Color onSurface) {
    return ElevatedButton.icon(
      onPressed: _canProcess ? _processAllImages : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        disabledBackgroundColor: onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: onSurface.withValues(alpha: 0.35),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      icon: _isProcessing
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.center_focus_strong_rounded, size: 17),
      label: Text(
        _isProcessing ? 'CENTERING $_processedCount/${_images.length}' : 'CENTER IMAGES',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.65),
      ),
    );
  }

  Widget _buildFolderBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        border: Border.all(color: onSurface.withValues(alpha: 0.11)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_open_rounded, size: 21, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SOURCE FOLDER',
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _folderPath.isEmpty ? 'Choose a folder to load its PNG files' : _folderPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    color: _folderPath.isEmpty ? onSurface.withValues(alpha: 0.5) : onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _pickFolder,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.folder_rounded, size: 16),
            label: const Text('BROWSE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _folderPath.isEmpty || _isLoadingFolder || _isProcessing ? null : _loadImages,
            tooltip: 'Reload PNG files',
            icon: const Icon(Icons.refresh_rounded, size: 19),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildAspectBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.025),
        border: Border.all(color: onSurface.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'OUTPUT ASPECT RATIO',
                style: TextStyle(
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: accent.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _aspectDescription,
                  style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.55)),
                ),
              ),
              if (_folderPath.isNotEmpty)
                Text(
                  '${_images.length} PNG${_images.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.55)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _CenterImageAspectPreset.values
                    .map((_CenterImageAspectPreset preset) => _buildAspectChip(preset, accent, onSurface))
                    .toList(),
              ),
              const Spacer(),
              _buildCenterAction(accent, onSurface),
            ],
          ),
          if (_aspectPreset == _CenterImageAspectPreset.custom) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Custom ratio', style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface)),
                const SizedBox(width: 8),
                _buildRatioInput(_customWidthController, accent, onSurface),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child:
                      Text(':', style: TextStyle(fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.6))),
                ),
                _buildRatioInput(_customHeightController, accent, onSurface),
                if (_aspectRatio == null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    'Enter two positive numbers',
                    style: TextStyle(fontSize: Design.baseFontSize, color: Colors.orange.shade700),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAspectChip(_CenterImageAspectPreset preset, Color accent, Color onSurface) {
    final bool selected = _aspectPreset == preset;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => _setAspectPreset(preset),
      label: Text(_aspectLabel(preset)),
      labelStyle: TextStyle(
        fontSize: Design.baseFontSize,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? accent : onSurface.withValues(alpha: 0.75),
      ),
      selectedColor: accent.withValues(alpha: 0.13),
      backgroundColor: onSurface.withValues(alpha: 0.035),
      side: BorderSide(color: selected ? accent.withValues(alpha: 0.55) : onSurface.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 3),
    );
  }

  Widget _buildRatioInput(TextEditingController controller, Color accent, Color onSurface) {
    return SizedBox(
      width: 52,
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: (_) => _onCustomRatioChanged(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: onSurface.withValues(alpha: 0.18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.8)),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspace(Color accent, Color onSurface) {
    if (_isLoadingFolder) return _buildLoadingState(onSurface);
    if (_images.isEmpty) return _buildEmptyState(accent, onSurface);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget fileList = _buildImageList(accent, onSurface);
        final Widget preview = _buildPreview(accent, onSurface);

        if (constraints.maxWidth < 760) {
          return Column(
            children: <Widget>[
              SizedBox(height: 188, child: fileList),
              const SizedBox(height: 10),
              Expanded(child: preview),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 272, child: fileList),
            const SizedBox(width: 10),
            Expanded(child: preview),
          ],
        );
      },
    );
  }

  Widget _buildLoadingState(Color onSurface) {
    return _workspaceShell(
      onSurface,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.2)),
            const SizedBox(height: 10),
            Text('Loading PNG files…',
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.65))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color accent, Color onSurface) {
    final String message;
    final String detail;
    if (_folderError != null) {
      message = 'Folder could not be read';
      detail = _folderError!;
    } else if (_folderPath.isEmpty) {
      message = 'Choose a source folder';
      detail = 'PNG files from that folder will appear here for review.';
    } else {
      message = 'No PNG files found';
      detail = 'Choose a folder containing transparent PNG images, then preview the first file here.';
    }

    return _workspaceShell(
      onSurface,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.photo_library_outlined, size: 42, color: accent.withValues(alpha: 0.55)),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(fontSize: Design.baseFontSize + 4, fontWeight: FontWeight.w700, color: onSurface)),
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.55)),
              ),
            ),
            if (_folderPath.isEmpty) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 17),
                label: const Text('Choose folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _workspaceShell(Color onSurface, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.018),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }

  Widget _buildImageList(Color accent, Color onSurface) {
    return Container(
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.018),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 9, 8),
            child: Row(
              children: <Widget>[
                Text(
                  'PNG FILES',
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_images.length}',
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: onSurface.withValues(alpha: 0.09)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(6),
              itemCount: _images.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (BuildContext context, int index) => _buildImageListItem(index, accent, onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageListItem(int index, Color accent, Color onSurface) {
    final _CenterImageEntry entry = _images[index];
    final bool selected = index == _selectedIndex;
    final _CenterImageAnalysis? analysis = entry.analysis;
    final String detail;
    if (entry.error != null) {
      detail = 'Could not decode';
    } else if (analysis != null && analysis.sourceWidth > 0) {
      detail = '${analysis.sourceWidth} × ${analysis.sourceHeight}';
    } else {
      detail = 'Select to preview';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectImage(index),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.1) : onSurface.withValues(alpha: 0.018),
            border: Border.all(color: selected ? accent.withValues(alpha: 0.6) : onSurface.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: <Widget>[
              _buildThumbnail(entry.file, selected ? accent : onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _fileName(entry.file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        if (entry.isLoading)
                          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                        else if (analysis != null && analysis.hasTransparentMargin)
                          Icon(Icons.center_focus_strong_rounded, size: 11, color: accent)
                        else if (entry.error != null)
                          Icon(Icons.error_outline_rounded, size: 12, color: Colors.orange.shade700)
                        else
                          Icon(Icons.image_outlined, size: 11, color: onSurface.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.5)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(File file, Color borderColor) {
    return SizedBox(
      width: 52,
      height: 52,
      child: _buildCheckerboardFrame(
        borderColor: borderColor.withValues(alpha: 0.45),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, size: 21, color: borderColor.withValues(alpha: 0.55)),
        ),
      ),
    );
  }

  Widget _buildPreview(Color accent, Color onSurface) {
    final _CenterImageEntry entry = _images[_selectedIndex];
    final _CenterImageAnalysis? analysis = entry.analysis;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.018),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _fileName(entry.file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize + 4, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _previewDescription(analysis),
                      style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              if (entry.isLoading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          if (analysis == null || entry.error != null)
            Expanded(child: _buildPreviewLoading(entry, accent, onSurface))
          else ...<Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget source = _buildPreviewPanel(
                    label: 'SOURCE',
                    imageBytes: analysis.sourceBytes,
                    width: analysis.sourceWidth,
                    height: analysis.sourceHeight,
                    contentLeft: analysis.cropLeft,
                    contentTop: analysis.cropTop,
                    contentWidth: analysis.cropWidth,
                    contentHeight: analysis.cropHeight,
                    accent: accent,
                    onSurface: onSurface,
                    helperText: 'Accent border = visible pixels',
                  );
                  final Widget output = _buildPreviewPanel(
                    label: 'CENTERED OUTPUT',
                    imageBytes: analysis.outputBytes,
                    width: analysis.outputWidth,
                    height: analysis.outputHeight,
                    contentLeft: analysis.outputContentLeft,
                    contentTop: analysis.outputContentTop,
                    contentWidth: analysis.cropWidth,
                    contentHeight: analysis.cropHeight,
                    accent: accent,
                    onSurface: onSurface,
                    helperText: 'Outer border = saved canvas',
                  );

                  if (constraints.maxWidth < 580) {
                    return Column(
                      children: <Widget>[
                        Expanded(child: source),
                        const SizedBox(height: 8),
                        Expanded(child: output),
                      ],
                    );
                  }

                  return Row(
                    children: <Widget>[
                      Expanded(child: source),
                      const SizedBox(width: 8),
                      Expanded(child: output),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _buildPreviewFooter(analysis, accent, onSurface),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewLoading(_CenterImageEntry entry, Color accent, Color onSurface) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (entry.error != null) ...<Widget>[
            Icon(Icons.broken_image_outlined, size: 38, color: Colors.orange.shade700),
            const SizedBox(height: 9),
            Text('This PNG could not be decoded.', style: TextStyle(color: onSurface.withValues(alpha: 0.7))),
          ] else ...<Widget>[
            CircularProgressIndicator(color: accent, strokeWidth: 2),
            const SizedBox(height: 9),
            Text('Reading image bounds…', style: TextStyle(color: onSurface.withValues(alpha: 0.6))),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewPanel({
    required String label,
    required Uint8List imageBytes,
    required int width,
    required int height,
    required int contentLeft,
    required int contentTop,
    required int contentWidth,
    required int contentHeight,
    required Color accent,
    required Color onSurface,
    required String helperText,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.025),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                    fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700, letterSpacing: 0.65, color: accent),
              ),
              const Spacer(),
              Text(
                '$width × $height px',
                style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _buildCanvasPreview(
              imageBytes: imageBytes,
              width: width,
              height: height,
              contentLeft: contentLeft,
              contentTop: contentTop,
              contentWidth: contentWidth,
              contentHeight: contentHeight,
              accent: accent,
              onSurface: onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            helperText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasPreview({
    required Uint8List imageBytes,
    required int width,
    required int height,
    required int contentLeft,
    required int contentTop,
    required int contentWidth,
    required int contentHeight,
    required Color accent,
    required Color onSurface,
  }) {
    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 240;
        final double maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 240;
        final double aspect = width / height;
        double previewWidth = maxWidth;
        double previewHeight = previewWidth / aspect;
        if (previewHeight > maxHeight) {
          previewHeight = maxHeight;
          previewWidth = previewHeight * aspect;
        }

        return Center(
          child: SizedBox(
            width: math.max(1.0, previewWidth),
            height: math.max(1.0, previewHeight),
            child: _buildCheckerboardFrame(
              borderColor: onSurface.withValues(alpha: 0.5),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.memory(
                    imageBytes,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.broken_image_outlined, color: onSurface.withValues(alpha: 0.55)),
                  ),
                  CustomPaint(
                    foregroundPainter: _ImageBoundsPainter(
                      contentLeft: contentLeft,
                      contentTop: contentTop,
                      contentWidth: contentWidth,
                      contentHeight: contentHeight,
                      canvasWidth: width,
                      canvasHeight: height,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckerboardFrame({required Color borderColor, required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('resources/images/checkerboard.png'),
          repeat: ImageRepeat.repeat,
        ),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _buildPreviewFooter(_CenterImageAnalysis analysis, Color accent, Color onSurface) {
    final String trimText = analysis.hasVisiblePixels
        ? '${analysis.cropWidth} × ${analysis.cropHeight} px visible'
        : 'No visible pixels detected';
    return Row(
      children: <Widget>[
        Icon(
          analysis.hasTransparentMargin ? Icons.content_cut_rounded : Icons.check_circle_outline_rounded,
          size: 16,
          color: analysis.hasTransparentMargin ? accent : onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            analysis.hasTransparentMargin
                ? 'Empty margins removed · $trimText'
                : 'No transparent outer margin · $trimText',
            style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.62)),
          ),
        ),
        Text(
          'Saves to \\Centered',
          style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.45)),
        ),
      ],
    );
  }

  Future<void> _pickFolder() async {
    try {
      final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select PNG image folder';
      final Directory? directory = dirPicker.getDirectory();
      if (directory == null || directory.path.isEmpty) return;

      setState(() {
        _folderPath = directory.path;
      });
      await _loadImages();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _folderError = 'Failed to open the folder picker: $error';
      });
    }
  }

  Future<void> _loadImages() async {
    final int request = ++_folderRequest;
    final String folderPath = _folderPath.trim();
    _previewRequest++;

    if (mounted) {
      setState(() {
        _isLoadingFolder = folderPath.isNotEmpty;
        _folderError = null;
        _images = <_CenterImageEntry>[];
        _selectedIndex = -1;
        _processedCount = 0;
        _processingErrorCount = 0;
      });
    }
    if (folderPath.isEmpty) return;

    try {
      final Directory directory = Directory(folderPath);
      if (!await directory.exists()) throw Exception('The selected folder no longer exists.');

      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in directory.list(followLinks: false)) {
        if (entity is File && _isPng(entity.path)) files.add(entity);
      }
      files.sort((File a, File b) => _fileName(a).toLowerCase().compareTo(_fileName(b).toLowerCase()));

      if (!mounted || request != _folderRequest) return;
      setState(() {
        _images = files.map(_CenterImageEntry.new).toList();
        _selectedIndex = _images.isEmpty ? -1 : 0;
        _isLoadingFolder = false;
      });

      if (_selectedIndex >= 0) await _loadPreview(_selectedIndex);
    } catch (error) {
      if (!mounted || request != _folderRequest) return;
      setState(() {
        _isLoadingFolder = false;
        _folderError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _selectImage(int index) async {
    if (index < 0 || index >= _images.length || index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    await _loadPreview(index);
  }

  Future<void> _loadPreview(int index) async {
    if (index < 0 || index >= _images.length) return;
    final _CenterImageEntry entry = _images[index];
    final int request = ++_previewRequest;
    final int folderRequest = _folderRequest;

    setState(() {
      entry.isLoading = true;
      entry.error = null;
    });

    try {
      final Uint8List bytes = await entry.file.readAsBytes();
      final _CenterImageAnalysis analysis = await compute(
        _analyzeCenterImage,
        _CenterImageJob(bytes: bytes, aspectRatio: _aspectRatio),
      );
      if (!mounted || request != _previewRequest || folderRequest != _folderRequest) return;
      setState(() {
        entry.analysis = analysis;
        entry.isLoading = false;
        entry.error = analysis.error;
      });
    } catch (error) {
      if (!mounted || request != _previewRequest || folderRequest != _folderRequest) return;
      setState(() {
        entry.isLoading = false;
        entry.error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _recomputeSelectedPreview() async {
    if (_selectedIndex < 0 || _selectedIndex >= _images.length) return;
    final _CenterImageEntry entry = _images[_selectedIndex];
    final _CenterImageAnalysis? previous = entry.analysis;
    if (previous == null) {
      await _loadPreview(_selectedIndex);
      return;
    }

    final int request = ++_previewRequest;
    final int folderRequest = _folderRequest;
    setState(() {
      entry.isLoading = true;
      entry.error = null;
    });

    try {
      final _CenterImageAnalysis analysis = await compute(
        _analyzeCenterImage,
        _CenterImageJob(bytes: previous.sourceBytes, aspectRatio: _aspectRatio),
      );
      if (!mounted || request != _previewRequest || folderRequest != _folderRequest) return;
      setState(() {
        entry.analysis = analysis;
        entry.isLoading = false;
        entry.error = analysis.error;
      });
    } catch (error) {
      if (!mounted || request != _previewRequest || folderRequest != _folderRequest) return;
      setState(() {
        entry.isLoading = false;
        entry.error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _setAspectPreset(_CenterImageAspectPreset preset) async {
    if (_aspectPreset == preset) return;
    setState(() => _aspectPreset = preset);
    await _recomputeSelectedPreview();
  }

  void _onCustomRatioChanged() {
    if (mounted) setState(() {});
    _customRatioDebounce?.cancel();
    _customRatioDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _aspectPreset == _CenterImageAspectPreset.custom && _aspectRatio != null) {
        _recomputeSelectedPreview();
      }
    });
  }

  Future<void> _processAllImages() async {
    final double? aspectRatio = _aspectRatio;
    if (!_canProcess) return;

    final Directory outputDirectory = Directory('$_folderPath\\Centered');
    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _processingErrorCount = 0;
    });

    try {
      await outputDirectory.create(recursive: true);
      for (final _CenterImageEntry entry in _images) {
        try {
          final Uint8List bytes = await entry.file.readAsBytes();
          final _CenterImageAnalysis analysis = await compute(
            _analyzeCenterImage,
            _CenterImageJob(bytes: bytes, aspectRatio: aspectRatio),
          );
          if (analysis.error != null) {
            _processingErrorCount++;
          } else {
            final File outputFile = File('${outputDirectory.path}\\${_fileName(entry.file)}');
            await outputFile.writeAsBytes(analysis.outputBytes, flush: true);
          }
        } catch (_) {
          _processingErrorCount++;
        }

        if (mounted) {
          setState(() => _processedCount++);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create output folder: $error')));
      }
      return;
    }

    if (!mounted) return;
    final int savedCount = _processedCount - _processingErrorCount;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _processingErrorCount == 0
              ? 'Centered $savedCount PNG${savedCount == 1 ? '' : 's'} in ${outputDirectory.path}'
              : 'Saved $savedCount PNG${savedCount == 1 ? '' : 's'}; $_processingErrorCount could not be processed.',
        ),
      ),
    );
  }

  String _folderFromArguments() {
    for (final String argument in user.args) {
      final String cleaned = argument.replaceAll('"', '').trim();
      if (cleaned.isNotEmpty && cleaned != '-wizardly') return cleaned;
    }
    return '';
  }

  bool get _canProcess =>
      _folderPath.isNotEmpty &&
      _images.isNotEmpty &&
      !_isLoadingFolder &&
      !_isProcessing &&
      (_aspectPreset == _CenterImageAspectPreset.tight || _aspectRatio != null);

  double? get _aspectRatio {
    switch (_aspectPreset) {
      case _CenterImageAspectPreset.tight:
        return null;
      case _CenterImageAspectPreset.square:
        return 1;
      case _CenterImageAspectPreset.rectangle:
        return 4 / 3;
      case _CenterImageAspectPreset.portrait:
        return 4 / 5;
      case _CenterImageAspectPreset.wide:
        return 16 / 9;
      case _CenterImageAspectPreset.custom:
        final double? width = double.tryParse(_customWidthController.text.trim());
        final double? height = double.tryParse(_customHeightController.text.trim());
        if (width == null || height == null || width <= 0 || height <= 0) return null;
        return width / height;
    }
  }

  String get _aspectDescription {
    switch (_aspectPreset) {
      case _CenterImageAspectPreset.tight:
        return 'Crop to the visible pixels; each output keeps its natural ratio.';
      case _CenterImageAspectPreset.square:
        return 'Trim first, then center the visible pixels on a 1:1 transparent canvas.';
      case _CenterImageAspectPreset.rectangle:
        return 'Trim first, then center the visible pixels on a 4:3 transparent canvas.';
      case _CenterImageAspectPreset.portrait:
        return 'Trim first, then center the visible pixels on a 4:5 transparent canvas.';
      case _CenterImageAspectPreset.wide:
        return 'Trim first, then center the visible pixels on a 16:9 transparent canvas.';
      case _CenterImageAspectPreset.custom:
        return _aspectRatio == null
            ? 'Custom ratio is incomplete.'
            : 'Trim first, then center on your custom canvas ratio.';
    }
  }

  String _previewDescription(_CenterImageAnalysis? analysis) {
    if (analysis == null) return 'Select an image to calculate its transparent bounds.';
    if (analysis.error != null) return analysis.error!;
    return '${analysis.sourceWidth} × ${analysis.sourceHeight} px source  →  ${analysis.outputWidth} × ${analysis.outputHeight} px output';
  }

  String _aspectLabel(_CenterImageAspectPreset preset) {
    switch (preset) {
      case _CenterImageAspectPreset.tight:
        return 'Tight bounds';
      case _CenterImageAspectPreset.square:
        return 'Square 1:1';
      case _CenterImageAspectPreset.rectangle:
        return 'Rectangle 4:3';
      case _CenterImageAspectPreset.portrait:
        return 'Portrait 4:5';
      case _CenterImageAspectPreset.wide:
        return 'Wide 16:9';
      case _CenterImageAspectPreset.custom:
        return 'Custom';
    }
  }

  static bool _isPng(String path) => path.toLowerCase().endsWith('.png');

  static String _fileName(File file) => file.path.split(RegExp(r'[\\/]')).last;
}

_CenterImageAnalysis _analyzeCenterImage(_CenterImageJob job) {
  final img.Image? source = img.decodeImage(job.bytes);
  if (source == null) {
    return _CenterImageAnalysis(
      sourceBytes: job.bytes,
      outputBytes: job.bytes,
      sourceWidth: 0,
      sourceHeight: 0,
      outputWidth: 0,
      outputHeight: 0,
      cropLeft: 0,
      cropTop: 0,
      cropWidth: 0,
      cropHeight: 0,
      outputContentLeft: 0,
      outputContentTop: 0,
      hasVisiblePixels: false,
      hasTransparentMargin: false,
      error: 'Could not decode this PNG.',
    );
  }

  int left = source.width;
  int top = source.height;
  int right = -1;
  int bottom = -1;

  for (int y = 0; y < source.height; y++) {
    for (int x = 0; x < source.width; x++) {
      final img.Pixel pixel = source.getPixel(x, y);
      if (!source.hasAlpha || pixel.a.toDouble() > _ImageToolsState._alphaThreshold) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }

  if (right < left || bottom < top) {
    return _CenterImageAnalysis(
      sourceBytes: job.bytes,
      outputBytes: job.bytes,
      sourceWidth: source.width,
      sourceHeight: source.height,
      outputWidth: source.width,
      outputHeight: source.height,
      cropLeft: 0,
      cropTop: 0,
      cropWidth: 0,
      cropHeight: 0,
      outputContentLeft: 0,
      outputContentTop: 0,
      hasVisiblePixels: false,
      hasTransparentMargin: false,
    );
  }

  final int cropWidth = right - left + 1;
  final int cropHeight = bottom - top + 1;
  final img.Image cropped = img.copyCrop(
    source,
    x: left,
    y: top,
    width: cropWidth,
    height: cropHeight,
  );

  int outputWidth = cropWidth;
  int outputHeight = cropHeight;
  final double? aspectRatio = job.aspectRatio;
  if (aspectRatio != null && aspectRatio > 0) {
    final double cropAspect = cropWidth / cropHeight;
    if (cropAspect >= aspectRatio) {
      outputWidth = cropWidth;
      outputHeight = (cropWidth / aspectRatio).ceil();
    } else {
      outputWidth = (cropHeight * aspectRatio).ceil();
      outputHeight = cropHeight;
    }
  }

  final img.Image output = img.Image(width: outputWidth, height: outputHeight, numChannels: 4);
  img.fill(output, color: img.ColorRgba8(0, 0, 0, 0));
  final int outputContentLeft = (outputWidth - cropWidth) ~/ 2;
  final int outputContentTop = (outputHeight - cropHeight) ~/ 2;
  img.compositeImage(output, cropped, dstX: outputContentLeft, dstY: outputContentTop);

  return _CenterImageAnalysis(
    sourceBytes: job.bytes,
    outputBytes: Uint8List.fromList(img.encodePng(output)),
    sourceWidth: source.width,
    sourceHeight: source.height,
    outputWidth: outputWidth,
    outputHeight: outputHeight,
    cropLeft: left,
    cropTop: top,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
    outputContentLeft: outputContentLeft,
    outputContentTop: outputContentTop,
    hasVisiblePixels: true,
    hasTransparentMargin: left > 0 || top > 0 || right < source.width - 1 || bottom < source.height - 1,
  );
}

class _ImageBoundsPainter extends CustomPainter {
  const _ImageBoundsPainter({
    required this.contentLeft,
    required this.contentTop,
    required this.contentWidth,
    required this.contentHeight,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.color,
  });

  final int contentLeft;
  final int contentTop;
  final int contentWidth;
  final int contentHeight;
  final int canvasWidth;
  final int canvasHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint outerPaint = Paint()
      ..color = color.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final Paint innerPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final double outerWidth = size.width > 1.2 ? size.width - 1.2 : 0;
    final double outerHeight = size.height > 1.2 ? size.height - 1.2 : 0;
    canvas.drawRect(Rect.fromLTWH(0.6, 0.6, outerWidth, outerHeight), outerPaint);
    if (contentWidth <= 0 || contentHeight <= 0 || canvasWidth <= 0 || canvasHeight <= 0) return;

    final Rect contentRect = Rect.fromLTWH(
      size.width * contentLeft / canvasWidth,
      size.height * contentTop / canvasHeight,
      size.width * contentWidth / canvasWidth,
      size.height * contentHeight / canvasHeight,
    );
    canvas.drawRect(contentRect, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _ImageBoundsPainter oldDelegate) =>
      contentLeft != oldDelegate.contentLeft ||
      contentTop != oldDelegate.contentTop ||
      contentWidth != oldDelegate.contentWidth ||
      contentHeight != oldDelegate.contentHeight ||
      canvasWidth != oldDelegate.canvasWidth ||
      canvasHeight != oldDelegate.canvasHeight ||
      color != oldDelegate.color;
}
