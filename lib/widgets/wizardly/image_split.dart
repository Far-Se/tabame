import 'dart:io';
import 'dart:math' as math;

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../models/settings.dart';

const Set<String> _splitImageExtensions = <String>{'.png', '.jpg', '.jpeg', '.bmp', '.gif'};

enum _SplitLineAxis {
  row,
  column,
}

class _SplitLineHit {
  const _SplitLineHit({required this.axis, required this.index});

  final _SplitLineAxis axis;
  final int index;
}

class _SplitImageInspectJob {
  const _SplitImageInspectJob(this.bytes);

  final Uint8List bytes;
}

class _SplitImageInfo {
  const _SplitImageInfo({required this.width, required this.height, this.error});

  final int width;
  final int height;
  final String? error;
}

class _SplitImageJob {
  const _SplitImageJob({
    required this.bytes,
    required this.rowCuts,
    required this.columnCuts,
    required this.extension,
  });

  final Uint8List bytes;
  final List<int> rowCuts;
  final List<int> columnCuts;
  final String extension;
}

class _SplitImageResult {
  const _SplitImageResult({required this.tiles, this.error});

  final List<Uint8List> tiles;
  final String? error;
}

/// Splits a loaded image into a row/column grid while keeping the source file unchanged.
class ImageSplitTool extends StatefulWidget {
  const ImageSplitTool({super.key});

  @override
  State<ImageSplitTool> createState() => _ImageSplitToolState();
}

class _ImageSplitToolState extends State<ImageSplitTool> {
  late final TextEditingController _rowsController;
  late final TextEditingController _columnsController;

  File? _sourceFile;
  Uint8List? _sourceBytes;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  int _rows = 2;
  int _columns = 2;
  List<int> _rowDividers = <int>[];
  List<int> _columnDividers = <int>[];
  _SplitLineHit? _draggedLine;
  bool _isLoading = false;
  bool _isSplitting = false;
  int _splitProgress = 0;
  String? _error;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _rowsController = TextEditingController(text: '2');
    _columnsController = TextEditingController(text: '2');
  }

  @override
  void dispose() {
    _rowsController.dispose();
    _columnsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSourceBar(accent, onSurface),
          const SizedBox(height: 10),
          _buildGridControls(accent, onSurface),
          const SizedBox(height: 10),
          Expanded(child: _buildPreview(accent, onSurface)),
        ],
      ),
    );
  }

  Widget _buildSourceBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        border: Border.all(color: onSurface.withValues(alpha: 0.11)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.image_outlined, size: 22, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SOURCE IMAGE',
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _sourceFile == null ? 'Choose one image to split' : _sourceFile!.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    color: _sourceFile == null ? onSurface.withValues(alpha: 0.5) : onSurface,
                  ),
                ),
                if (_sourceFile != null && _sourceWidth > 0)
                  Text(
                    '$_sourceWidth × $_sourceHeight px  ·  ${_extension(_sourceFile!.path)} format preserved',
                    style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.5)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _isSplitting ? null : _pickImage,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.file_open_rounded, size: 16),
            label: const Text('OPEN IMAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildGridControls(Color accent, Color onSurface) {
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
                'SPLIT GRID',
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
                  'Adjust rows and columns, then drag lines to match the source image.',
                  style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.55)),
                ),
              ),
              Text(
                '$_gridCount FILES',
                style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _buildStepper(
                label: 'ROWS',
                value: _rows,
                maxValue: _maxRows,
                enabled: !_isSplitting,
                controller: _rowsController,
                accent: accent,
                onSurface: onSurface,
                onChanged: _onRowsChanged,
                onEditingComplete: _normalizeRows,
                onDecrease: () => _setRows(_rows - 1),
                onIncrease: () => _setRows(_rows + 1),
              ),
              Text('×',
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 4,
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.45))),
              _buildStepper(
                label: 'COLUMNS',
                value: _columns,
                maxValue: _maxColumns,
                enabled: !_isSplitting,
                controller: _columnsController,
                accent: accent,
                onSurface: onSurface,
                onChanged: _onColumnsChanged,
                onEditingComplete: _normalizeColumns,
                onDecrease: () => _setColumns(_columns - 1),
                onIncrease: () => _setColumns(_columns + 1),
              ),
              OutlinedButton.icon(
                onPressed: _sourceBytes == null || _isSplitting ? null : _resetDividers,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('RESET LINES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              _buildOutputHint(accent, onSurface),
              ElevatedButton.icon(
                onPressed: _canSplit ? _splitImage : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  disabledBackgroundColor: onSurface.withValues(alpha: 0.08),
                  disabledForegroundColor: onSurface.withValues(alpha: 0.35),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSplitting
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.grid_view_rounded, size: 17),
                label: Text(
                  _isSplitting ? 'SPLITTING $_splitProgress/$_gridCount' : 'SPLIT IMAGE',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepper({
    required String label,
    required int value,
    required int maxValue,
    required bool enabled,
    required TextEditingController controller,
    required Color accent,
    required Color onSurface,
    required ValueChanged<String> onChanged,
    required VoidCallback onEditingComplete,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        border: Border.all(color: onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.55,
                color: onSurface.withValues(alpha: 0.62)),
          ),
          const SizedBox(width: 5),
          _stepperButton(
            icon: Icons.remove_rounded,
            onPressed: enabled && value > 1 ? onDecrease : null,
            color: onSurface,
          ),
          SizedBox(
            width: 38,
            height: 19,
            child: TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onChanged,
              onEditingComplete: onEditingComplete,
              onSubmitted: (_) => onEditingComplete(),
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: accent),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: accent.withValues(alpha: 0.8)),
                ),
              ),
            ),
          ),
          _stepperButton(
            icon: Icons.add_rounded,
            onPressed: enabled && value < maxValue ? onIncrease : null,
            color: onSurface,
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, required VoidCallback? onPressed, required Color color}) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      color: color.withValues(alpha: onPressed == null ? 0.22 : 0.65),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 26),
      visualDensity: VisualDensity.compact,
      splashRadius: 14,
    );
  }

  Widget _buildOutputHint(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        _sourceFile == null
            ? 'Output: choose an image first'
            : 'Output: \\${_sourceFile!.parent.path.split(RegExp(r'[\\/]')).last}\\Split',
        style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.65)),
      ),
    );
  }

  Widget _buildPreview(Color accent, Color onSurface) {
    if (_isLoading) {
      return _previewShell(
        onSurface,
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_sourceBytes == null || _sourceWidth <= 0 || _sourceHeight <= 0) {
      return _previewShell(
        onSurface,
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.grid_view_rounded, size: 43, color: accent.withValues(alpha: 0.55)),
              const SizedBox(height: 12),
              Text('Load one image to begin',
                  style: TextStyle(fontSize: Design.baseFontSize + 4, fontWeight: FontWeight.w700, color: onSurface)),
              const SizedBox(height: 5),
              Text(
                _error ?? 'The preview shows the exact row and column cuts before anything is written.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  color: _error == null ? onSurface.withValues(alpha: 0.55) : Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.file_open_rounded, size: 17),
                label: const Text('Open image'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                    Text('GRID PREVIEW',
                        style: TextStyle(
                            fontSize: Design.baseFontSize - 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.65,
                            color: accent)),
                    const SizedBox(height: 3),
                    Text(
                      '$_rows rows × $_columns columns  ·  $_gridCount output files',
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Flexible(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: Design.baseFontSize, color: Colors.orange.shade700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _buildCanvasPreview(accent, onSurface),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: 16, color: onSurface.withValues(alpha: 0.48)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Drag cyan divider lines to move a cut. Files are named from 1: top-to-bottom rows, then left-to-right columns.',
                  style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.55)),
                ),
              ),
              Text(
                'Original stays unchanged',
                style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withValues(alpha: 0.45)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasPreview(Color accent, Color onSurface) {
    final Uint8List bytes = _sourceBytes!;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 420;
        final double maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 320;
        final double aspect = _sourceWidth / _sourceHeight;
        double width = maxWidth;
        double height = width / aspect;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * aspect;
        }
        final double previewWidth = math.max(1.0, width);
        final double previewHeight = math.max(1.0, height);
        final Size previewSize = Size(previewWidth, previewHeight);

        return Center(
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: _buildCheckerboardFrame(
              borderColor: onSurface.withValues(alpha: 0.55),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails details) => _handlePanStart(details.localPosition, previewSize),
                onPanUpdate: (DragUpdateDetails details) => _handlePanUpdate(details.localPosition, previewSize),
                onPanEnd: (_) => _handlePanEnd(),
                onPanCancel: _handlePanEnd,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.memory(bytes, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    CustomPaint(
                      foregroundPainter: _SplitGridPainter(
                        rowDividers: _rowDividers,
                        columnDividers: _columnDividers,
                        sourceWidth: _sourceWidth,
                        sourceHeight: _sourceHeight,
                        activeLine: _draggedLine,
                        gridColor: accent,
                        borderColor: onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePanStart(Offset position, Size previewSize) {
    final _SplitLineHit? hit = _hitTestLine(position, previewSize);
    if (hit == null) return;
    setState(() => _draggedLine = hit);
  }

  void _handlePanUpdate(Offset position, Size previewSize) {
    final _SplitLineHit? draggedLine = _draggedLine;
    if (draggedLine == null || previewSize.width <= 0 || previewSize.height <= 0) return;

    if (draggedLine.axis == _SplitLineAxis.column) {
      final int proposed = (position.dx / previewSize.width * _sourceWidth).round();
      final int previous = draggedLine.index == 0 ? 0 : _columnDividers[draggedLine.index - 1];
      final int next =
          draggedLine.index == _columnDividers.length - 1 ? _sourceWidth : _columnDividers[draggedLine.index + 1];
      final int value = proposed.clamp(previous + 1, next - 1).toInt();
      if (value == _columnDividers[draggedLine.index]) return;
      setState(() => _columnDividers[draggedLine.index] = value);
      return;
    }

    final int proposed = (position.dy / previewSize.height * _sourceHeight).round();
    final int previous = draggedLine.index == 0 ? 0 : _rowDividers[draggedLine.index - 1];
    final int next = draggedLine.index == _rowDividers.length - 1 ? _sourceHeight : _rowDividers[draggedLine.index + 1];
    final int value = proposed.clamp(previous + 1, next - 1).toInt();
    if (value == _rowDividers[draggedLine.index]) return;
    setState(() => _rowDividers[draggedLine.index] = value);
  }

  void _handlePanEnd() {
    if (_draggedLine != null) setState(() => _draggedLine = null);
  }

  _SplitLineHit? _hitTestLine(Offset position, Size previewSize) {
    const double hitDistance = 11;
    _SplitLineHit? closest;
    double closestDistance = hitDistance;

    for (int index = 0; index < _columnDividers.length; index++) {
      final double x = previewSize.width * _columnDividers[index] / _sourceWidth;
      final double distance = (position.dx - x).abs();
      if (distance <= closestDistance) {
        closestDistance = distance;
        closest = _SplitLineHit(axis: _SplitLineAxis.column, index: index);
      }
    }
    for (int index = 0; index < _rowDividers.length; index++) {
      final double y = previewSize.height * _rowDividers[index] / _sourceHeight;
      final double distance = (position.dy - y).abs();
      if (distance <= closestDistance) {
        closestDistance = distance;
        closest = _SplitLineHit(axis: _SplitLineAxis.row, index: index);
      }
    }
    return closest;
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

  Widget _previewShell(Color onSurface, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.018),
        border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }

  Future<void> _pickImage() async {
    try {
      final OpenFilePicker picker = OpenFilePicker()
        ..filterSpecification = <String, String>{
          'Image Files (*.png; *.jpg; *.jpeg; *.bmp; *.gif)': '*.png;*.jpg;*.jpeg;*.bmp;*.gif',
          'All Files': '*.*',
        }
        ..defaultFilterIndex = 0
        ..title = 'Select an image to split';
      final File? file = picker.getFile();
      if (file == null) return;

      final int request = ++_loadRequest;
      setState(() {
        _sourceFile = file;
        _sourceBytes = null;
        _sourceWidth = 0;
        _sourceHeight = 0;
        _isLoading = true;
        _error = null;
      });

      final Uint8List bytes = await file.readAsBytes();
      final _SplitImageInfo info = await compute(_inspectSplitImage, _SplitImageInspectJob(bytes));
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _sourceBytes = info.error == null ? bytes : null;
        _sourceWidth = info.width;
        _sourceHeight = info.height;
        _rows = _rows.clamp(1, _maxRows).toInt();
        _columns = _columns.clamp(1, _maxColumns).toInt();
        _syncGridControllers();
        _resetDividersWithoutSetState();
        _isLoading = false;
        _error = info.error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _sourceBytes = null;
        _sourceWidth = 0;
        _sourceHeight = 0;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _splitImage() async {
    final File? sourceFile = _sourceFile;
    final Uint8List? sourceBytes = _sourceBytes;
    if (!_canSplit || sourceFile == null || sourceBytes == null) return;
    final int rows = _rows;
    final int columns = _columns;
    final List<int> rowCuts = <int>[0, ..._rowDividers, _sourceHeight];
    final List<int> columnCuts = <int>[0, ..._columnDividers, _sourceWidth];

    setState(() {
      _isSplitting = true;
      _splitProgress = 0;
      _error = null;
    });

    try {
      final String extension = _extension(sourceFile.path);
      final _SplitImageResult result = await compute(
        _splitImageIntoTiles,
        _SplitImageJob(
          bytes: sourceBytes,
          rowCuts: rowCuts,
          columnCuts: columnCuts,
          extension: extension,
        ),
      );
      if (result.error != null) throw Exception(result.error);

      final Directory outputDirectory = Directory('${sourceFile.parent.path}\\Split');
      await outputDirectory.create(recursive: true);
      final String baseName = _baseName(sourceFile.path);
      int tileIndex = 0;
      for (int row = 1; row <= rows; row++) {
        for (int column = 1; column <= columns; column++) {
          final File outputFile = File('${outputDirectory.path}\\${baseName}_${row}_$column$extension');
          await outputFile.writeAsBytes(result.tiles[tileIndex++], flush: true);
          if (mounted) setState(() => _splitProgress = tileIndex);
        }
      }

      if (!mounted) return;
      setState(() => _isSplitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${result.tiles.length} files in ${outputDirectory.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSplitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image split failed: $_error')));
    }
  }

  void _onRowsChanged(String value) {
    final int? parsed = int.tryParse(value);
    if (parsed != null && parsed >= 1 && parsed <= _maxRows && parsed != _rows) {
      setState(() {
        _rows = parsed;
        _resetDividersWithoutSetState();
      });
    }
  }

  void _onColumnsChanged(String value) {
    final int? parsed = int.tryParse(value);
    if (parsed != null && parsed >= 1 && parsed <= _maxColumns && parsed != _columns) {
      setState(() {
        _columns = parsed;
        _resetDividersWithoutSetState();
      });
    }
  }

  void _normalizeRows() => _setRows(int.tryParse(_rowsController.text) ?? _rows);

  void _normalizeColumns() => _setColumns(int.tryParse(_columnsController.text) ?? _columns);

  void _setRows(int value) {
    final int normalized = value.clamp(1, _maxRows).toInt();
    setState(() {
      _rows = normalized;
      _syncGridControllers();
      _resetDividersWithoutSetState();
    });
  }

  void _setColumns(int value) {
    final int normalized = value.clamp(1, _maxColumns).toInt();
    setState(() {
      _columns = normalized;
      _syncGridControllers();
      _resetDividersWithoutSetState();
    });
  }

  void _resetDividers() {
    setState(_resetDividersWithoutSetState);
  }

  void _resetDividersWithoutSetState() {
    _rowDividers = _evenDividers(_sourceHeight, _rows);
    _columnDividers = _evenDividers(_sourceWidth, _columns);
    _draggedLine = null;
  }

  void _syncGridControllers() {
    final String rowText = _rows.toString();
    final String columnText = _columns.toString();
    _rowsController.value = TextEditingValue(
      text: rowText,
      selection: TextSelection.collapsed(offset: rowText.length),
    );
    _columnsController.value = TextEditingValue(
      text: columnText,
      selection: TextSelection.collapsed(offset: columnText.length),
    );
  }

  List<int> _evenDividers(int size, int parts) {
    if (size <= 1 || parts <= 1) return <int>[];
    return List<int>.generate(parts - 1, (int index) => ((index + 1) * size / parts).round());
  }

  bool get _canSplit => _sourceBytes != null && !_isLoading && !_isSplitting;

  int get _gridCount => _rows * _columns;

  int get _maxRows => _sourceHeight <= 0 ? 64 : math.min(64, _sourceHeight);

  int get _maxColumns => _sourceWidth <= 0 ? 64 : math.min(64, _sourceWidth);

  static String _extension(String path) {
    final int index = path.lastIndexOf('.');
    if (index < 0) return '';
    return path.substring(index).toLowerCase();
  }

  static String _baseName(String path) {
    final String fileName = path.split(RegExp(r'[\\/]')).last;
    final int index = fileName.lastIndexOf('.');
    return index > 0 ? fileName.substring(0, index) : fileName;
  }
}

_SplitImageInfo _inspectSplitImage(_SplitImageInspectJob job) {
  final img.Image? decoded = img.decodeImage(job.bytes);
  if (decoded == null) return const _SplitImageInfo(width: 0, height: 0, error: 'Could not decode this image.');
  final img.Image image = decoded.getFrame(0);
  return _SplitImageInfo(width: image.width, height: image.height);
}

_SplitImageResult _splitImageIntoTiles(_SplitImageJob job) {
  final img.Image? decoded = img.decodeImage(job.bytes);
  if (decoded == null) return const _SplitImageResult(tiles: <Uint8List>[], error: 'Could not decode this image.');
  final img.Image source = decoded.getFrame(0);
  if (!_splitImageExtensions.contains(job.extension)) {
    return const _SplitImageResult(tiles: <Uint8List>[], error: 'This image format is not supported for export.');
  }
  if (!_validSplitCuts(job.rowCuts, source.height) || !_validSplitCuts(job.columnCuts, source.width)) {
    return const _SplitImageResult(tiles: <Uint8List>[], error: 'The split grid is invalid.');
  }

  final List<Uint8List> tiles = <Uint8List>[];
  for (int row = 0; row < job.rowCuts.length - 1; row++) {
    final int top = job.rowCuts[row];
    final int bottom = job.rowCuts[row + 1];
    for (int column = 0; column < job.columnCuts.length - 1; column++) {
      final int left = job.columnCuts[column];
      final int right = job.columnCuts[column + 1];
      final img.Image tile = img.copyCrop(
        source,
        x: left,
        y: top,
        width: math.max(1, right - left),
        height: math.max(1, bottom - top),
      );
      tiles.add(_encodeSplitTile(tile, job.extension));
    }
  }
  return _SplitImageResult(tiles: tiles);
}

bool _validSplitCuts(List<int> cuts, int size) {
  if (cuts.length < 2 || cuts.first != 0 || cuts.last != size) return false;
  for (int index = 1; index < cuts.length; index++) {
    if (cuts[index] <= cuts[index - 1]) return false;
  }
  return true;
}

Uint8List _encodeSplitTile(img.Image tile, String extension) {
  switch (extension) {
    case '.jpg':
    case '.jpeg':
      return Uint8List.fromList(img.encodeJpg(tile, quality: 95));
    case '.bmp':
      return Uint8List.fromList(img.encodeBmp(tile));
    case '.gif':
      return Uint8List.fromList(img.encodeGif(tile, singleFrame: true));
    case '.png':
    default:
      return Uint8List.fromList(img.encodePng(tile, singleFrame: true));
  }
}

class _SplitGridPainter extends CustomPainter {
  const _SplitGridPainter({
    required this.rowDividers,
    required this.columnDividers,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.activeLine,
    required this.gridColor,
    required this.borderColor,
  });

  final List<int> rowDividers;
  final List<int> columnDividers;
  final int sourceWidth;
  final int sourceHeight;
  final _SplitLineHit? activeLine;
  final Color gridColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint borderPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final Paint gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final Paint activePaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final double borderWidth = size.width > 1.2 ? size.width - 1.2 : 0;
    final double borderHeight = size.height > 1.2 ? size.height - 1.2 : 0;
    canvas.drawRect(Rect.fromLTWH(0.6, 0.6, borderWidth, borderHeight), borderPaint);

    for (int index = 0; index < columnDividers.length; index++) {
      final double x = size.width * columnDividers[index] / sourceWidth;
      final bool active = activeLine?.axis == _SplitLineAxis.column && activeLine?.index == index;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), active ? activePaint : gridPaint);
      if (active) canvas.drawCircle(Offset(x, size.height / 2), 4, activePaint);
    }
    for (int index = 0; index < rowDividers.length; index++) {
      final double y = size.height * rowDividers[index] / sourceHeight;
      final bool active = activeLine?.axis == _SplitLineAxis.row && activeLine?.index == index;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), active ? activePaint : gridPaint);
      if (active) canvas.drawCircle(Offset(size.width / 2, y), 4, activePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplitGridPainter oldDelegate) => true;
}
