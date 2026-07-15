import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/mix_widgets.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class WorkspacesButton extends StatelessWidget {
  const WorkspacesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: 'Workspaces',
      icon: const Icon(Icons.dashboard_customize_outlined),
      child: () => const WorkspacesPanel(),
    );
  }
}

class WorkspacesPanel extends StatefulWidget {
  const WorkspacesPanel({super.key});

  @override
  State<WorkspacesPanel> createState() => _WorkspacesPanelState();
}

class _WorkspacesPanelState extends State<WorkspacesPanel> {
  bool _isLaunching = false;
  String _launchStatus = '';

  // When non-null, the editor is open on a working copy of this workspace.
  Workspace? _editing;
  bool _isNew = false;

  List<Workspace> get _workspaces => Boxes.workspaces;

  Future<void> _launchWorkspace(Workspace workspace) async {
    if (_isLaunching) return;

    setState(() {
      _isLaunching = true;
      _launchStatus = 'Launching ${workspace.name}...';
    });

    try {
      await WorkspaceRunner.run(workspace);
    } finally {
      if (mounted) {
        setState(() {
          _isLaunching = false;
          _launchStatus = '';
        });
      }
      QuickMenuFunctions.hideQuickMenu();
    }
  }

  void _startCreate() {
    setState(() {
      _editing = Workspace(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'New Workspace ${_workspaces.length + 1}',
        areas: <WorkspaceArea>[],
      );
      _isNew = true;
    });
  }

  void _startEdit(Workspace workspace) {
    setState(() {
      _editing = workspace.copyWith();
      _isNew = false;
    });
  }

  /// Replace-or-append the working copy into the persisted list by id, so both
  /// the "edit" and "create new" flows share one write path.
  void _persist(Workspace updated) {
    final List<Workspace> list = List<Workspace>.from(_workspaces);
    final int index = list.indexWhere((Workspace w) => w.id == updated.id);
    if (index >= 0) {
      list[index] = updated;
    } else {
      list.add(updated);
    }
    Boxes.workspaces = list;
    _editing = updated;
    _isNew = false;
    if (mounted) setState(() {});
  }

  Future<void> _deleteWorkspace(Workspace workspace) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Delete workspace?'),
          content: Text('Remove "${workspace.name}" and all saved windows from this workspace?'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    Boxes.workspaces = List<Workspace>.from(_workspaces)..removeWhere((Workspace w) => w.id == workspace.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_editing != null) {
      return _WorkspaceEditor(
        key: ValueKey<String>('editor_${_editing!.id}'),
        workspace: _editing!,
        isNew: _isNew,
        onBack: () => setState(() => _editing = null),
        onSave: _persist,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Workspaces',
          icon: Icons.dashboard_customize_rounded,
          buttonPressed: _isLaunching ? null : _startCreate,
          buttonIcon: Icons.add_rounded,
          buttonTooltip: 'New Workspace',
        ),
        const SizedBox(height: 6),
        if (_isLaunching)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(color: Design.accent),
                    const SizedBox(height: 16),
                    Text(_launchStatus, style: TextStyle(color: Design.text, fontSize: Design.baseFontSize + 1)),
                  ],
                ),
              ),
            ),
          )
        else
          Flexible(
            child: Material(
              type: MaterialType.transparency,
              child: _workspaces.isEmpty
                  ? _WorkspacesEmptyState(onCreate: _startCreate)
                  : WindowsScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final Workspace workspace in _workspaces)
                              _WorkspaceRow(
                                key: ValueKey<String>(workspace.id),
                                workspace: workspace,
                                onLaunch: () => _launchWorkspace(workspace),
                                onEdit: () => _startEdit(workspace),
                                onDelete: () => _deleteWorkspace(workspace),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Geometry helpers (shared between capture, preview, and the area cards).
// ===========================================================================

/// Resolves the physical bounds of the monitor an area targets. Falls back to
/// the primary/first monitor for "auto" (monitorNumber <= 0) or disconnected
/// monitors, so px<->% conversions and previews always have something to scale
/// against.
Square? _monitorBoundsForNumber(int monitorNumber) {
  if (monitorNumber > 0) {
    for (final MapEntry<int, int> entry in Monitor.monitorIds.entries) {
      if (entry.value == monitorNumber) {
        final Square? bounds = Monitor.monitorSizes[entry.key];
        if (bounds != null) return bounds;
      }
    }
  }
  return Monitor.monitorSizes.values.isNotEmpty ? Monitor.monitorSizes.values.first : null;
}

/// Converts an area's geometry between fraction and pixel encodings, keeping the
/// same on-screen rect. LTRB is preserved in both modes (px are relative to the
/// monitor's top-left). A no-op when already in the requested mode or when the
/// monitor bounds are unknown.
WorkspaceArea _convertAreaMode(WorkspaceArea area, {required bool usePixels}) {
  if (area.usePixels == usePixels) return area;
  final Square? bounds = _monitorBoundsForNumber(area.monitorNumber);
  if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
    return area.copyWith(usePixels: usePixels);
  }
  final double w = bounds.width.toDouble();
  final double h = bounds.height.toDouble();
  if (usePixels) {
    return area.copyWith(
      usePixels: true,
      left: area.left * w,
      top: area.top * h,
      right: area.right * w,
      bottom: area.bottom * h,
    );
  }
  return area.copyWith(
    usePixels: false,
    left: (area.left / w).clamp(0.0, 1.0),
    top: (area.top / h).clamp(0.0, 1.0),
    right: (area.right / w).clamp(0.0, 1.0),
    bottom: (area.bottom / h).clamp(0.0, 1.0),
  );
}

// ===========================================================================
// Editor — one screen for both "edit existing" and "create new".
// ===========================================================================

class _WorkspaceEditor extends StatefulWidget {
  const _WorkspaceEditor({
    super.key,
    required this.workspace,
    required this.isNew,
    required this.onBack,
    required this.onSave,
  });

  final Workspace workspace;
  final bool isNew;
  final VoidCallback onBack;
  final ValueChanged<Workspace> onSave;

  @override
  State<_WorkspaceEditor> createState() => _WorkspaceEditorState();
}

class _WorkspaceEditorState extends State<_WorkspaceEditor> {
  late Workspace _workspace;
  late TextEditingController _nameController;
  late Future<void> _initialLoad;
  List<Window> _windows = <Window>[];
  String _windowQuery = '';
  int? _expandedAreaIndex;
  bool _refreshing = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace.copyWith();
    _nameController = TextEditingController(text: _workspace.name);
    _expandedAreaIndex = _workspace.areas.isEmpty ? null : 0;
    _initialLoad = _loadWindows();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _commit() {
    _dirty = true;
    widget.onSave(_workspace);
  }

  Future<void> _loadWindows() async {
    setState(() => _refreshing = true);
    await WindowWatcher.fetchWindows();
    if (!mounted) return;
    setState(() {
      _windows = List<Window>.from(WindowWatcher.list);
      _refreshing = false;
    });
  }

  void _renameWorkspace(String value) {
    setState(() {
      _workspace = _workspace.copyWith(name: value.trim().isEmpty ? _workspace.name : value.trim());
    });
    _commit();
  }

  WorkspaceArea _captureAreaFromWindow(Window window) {
    final int monitorHandle = window.monitor ?? Win32.getWindowMonitor(window.hWnd);
    final Square? monitorBounds = _monitorBoundsForHandle(monitorHandle);
    final Square windowBounds = Win32.getWindowRect(hwnd: window.hWnd);

    if (monitorBounds == null || monitorBounds.width <= 0 || monitorBounds.height <= 0) {
      return WorkspaceArea(
        left: 0.0,
        top: 0.0,
        right: 1.0,
        bottom: 1.0,
        monitorNumber: _monitorNumberForHandle(monitorHandle),
        windowTitle: window.title,
        executable: window.process.exePath,
      );
    }

    final double rawLeft = (windowBounds.x - monitorBounds.x) / monitorBounds.width;
    final double rawTop = (windowBounds.y - monitorBounds.y) / monitorBounds.height;
    final double rawRight = (windowBounds.x + windowBounds.width - monitorBounds.x) / monitorBounds.width;
    final double rawBottom = (windowBounds.y + windowBounds.height - monitorBounds.y) / monitorBounds.height;
    final double left = rawLeft.isFinite ? rawLeft.clamp(0.0, 1.0) : 0.0;
    final double top = rawTop.isFinite ? rawTop.clamp(0.0, 1.0) : 0.0;
    final double right = rawRight.isFinite ? rawRight.clamp(0.0, 1.0) : 1.0;
    final double bottom = rawBottom.isFinite ? rawBottom.clamp(0.0, 1.0) : 1.0;
    final double normalizedLeft = left <= right ? left : right;
    final double normalizedRight = right >= left ? right : left;
    final double normalizedTop = top <= bottom ? top : bottom;
    final double normalizedBottom = bottom >= top ? bottom : top;

    return WorkspaceArea(
      left: normalizedLeft,
      top: normalizedTop,
      right: normalizedRight,
      bottom: normalizedBottom,
      monitorNumber: _monitorNumberForHandle(monitorHandle),
      windowTitle: window.title,
      executable: window.process.exePath,
    );
  }

  void _addWindow(Window window) {
    setState(() {
      _workspace.areas = <WorkspaceArea>[..._workspace.areas, _captureAreaFromWindow(window)];
      _expandedAreaIndex = _workspace.areas.length - 1;
    });
    _commit();
  }

  void _deleteArea(int index) {
    setState(() {
      final List<WorkspaceArea> areas = List<WorkspaceArea>.from(_workspace.areas)..removeAt(index);
      _workspace = _workspace.copyWith(areas: areas);
      if (areas.isEmpty) {
        _expandedAreaIndex = null;
      } else if (_expandedAreaIndex != null && _expandedAreaIndex! >= areas.length) {
        _expandedAreaIndex = areas.length - 1;
      }
    });
    _commit();
  }

  void _updateArea(int index, WorkspaceArea updated) {
    setState(() {
      final List<WorkspaceArea> areas = List<WorkspaceArea>.from(_workspace.areas);
      areas[index] = updated;
      _workspace = _workspace.copyWith(areas: areas);
    });
    _commit();
  }

  void _refreshAreaFromLiveWindow(int index) {
    final WorkspaceArea area = _workspace.areas[index];
    final Window? match = _findMatchingWindow(area, _windows, <int>{});
    if (match == null) return;
    // Capture always yields fractions; convert to pixels if this area edits in px.
    final WorkspaceArea captured = _convertAreaMode(
      _captureAreaFromWindow(match).copyWith(
        executable: area.executable,
        parameters: area.parameters,
        hookTo: area.hookTo,
        hooks: List<String>.from(area.hooks),
        windowTitle: area.windowTitle,
      ),
      usePixels: area.usePixels,
    );
    _updateArea(index, captured);
  }

  Square? _monitorBoundsForHandle(int monitorHandle) {
    final Square? direct = Monitor.monitorSizes[monitorHandle];
    if (direct != null) return direct;
    if (Monitor.monitorSizes.isNotEmpty) return Monitor.monitorSizes.values.first;
    return null;
  }

  int _monitorNumberForHandle(int monitorHandle) {
    if (Monitor.monitorIds.containsKey(monitorHandle)) {
      return Monitor.monitorIds[monitorHandle]!;
    }
    return -1;
  }

  List<Window> _filteredWindows() {
    final String query = _windowQuery.trim().toLowerCase();
    if (query.isEmpty) return _windows;
    return _windows.where((Window window) {
      return window.title.toLowerCase().contains(query) ||
          window.process.exe.toLowerCase().contains(query) ||
          window.process.exePath.toLowerCase().contains(query);
    }).toList();
  }

  bool _windowMatchesArea(Window window, WorkspaceArea area) {
    final String windowExePath = window.process.exePath.toLowerCase();
    final String areaExePath = area.executable.toLowerCase();
    final String areaTitle = area.windowTitle.toLowerCase();
    final String windowTitle = window.title.toLowerCase();

    if (areaExePath.isEmpty) return false;

    final bool exeMatches =
        windowExePath == areaExePath || windowExePath.endsWith(areaExePath) || areaExePath.endsWith(windowExePath);
    if (!exeMatches) return false;

    if (areaTitle.isEmpty) return true;
    return windowTitle.contains(areaTitle) || areaTitle.contains(windowTitle);
  }

  Window? _findMatchingWindow(WorkspaceArea area, List<Window> windows, Set<int> usedHandles) {
    Window? bestWindow;
    int bestScore = -1;

    for (final Window window in windows) {
      if (usedHandles.contains(window.hWnd)) continue;
      if (!_windowMatchesArea(window, area)) continue;

      int score = 0;
      final String windowExePath = window.process.exePath.toLowerCase();
      final String areaExePath = area.executable.toLowerCase();
      final String windowTitle = window.title.toLowerCase();
      final String areaTitle = area.windowTitle.toLowerCase();

      if (windowExePath == areaExePath) {
        score += 40;
      } else if (windowExePath.endsWith(areaExePath) || areaExePath.endsWith(windowExePath)) {
        score += 25;
      }

      if (areaTitle.isNotEmpty) {
        if (windowTitle == areaTitle) {
          score += 20;
        } else if (windowTitle.contains(areaTitle) || areaTitle.contains(windowTitle)) {
          score += 10;
        }
      }

      if (area.monitorNumber > 0) {
        final int windowMonitorNumber = _monitorNumberForHandle(window.monitor ?? Win32.getWindowMonitor(window.hWnd));
        if (windowMonitorNumber == area.monitorNumber) score += 5;
      }

      if (score > bestScore) {
        bestScore = score;
        bestWindow = window;
      }
    }

    return bestWindow;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: FutureBuilder<void>(
              future: _initialLoad,
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                final List<Window> windows = _filteredWindows();
                return WindowsScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildPreviewCard(),
                        const SizedBox(height: 14),
                        _buildSectionLabel(
                          label: 'Current Windows',
                          count: windows.length,
                          icon: Icons.desktop_windows_rounded,
                        ),
                        const SizedBox(height: 8),
                        _buildSearchField(),
                        const SizedBox(height: 8),
                        if (windows.isEmpty)
                          _MiniEmptyState(
                            icon: Icons.window_rounded,
                            title: _windows.isEmpty ? 'No open windows found' : 'No windows match your search',
                            message: _windows.isEmpty
                                ? 'Open the apps you want to capture, then refresh.'
                                : 'Try a different keyword or clear the filter.',
                          )
                        else
                          for (final Window window in windows) ...<Widget>[
                            _CurrentWindowTile(window: window, onAdd: () => _addWindow(window)),
                            const SizedBox(height: 6),
                          ],
                        const SizedBox(height: 10),
                        _buildSectionLabel(
                          label: 'Selected Apps',
                          count: _workspace.areas.length,
                          icon: Icons.dashboard_customize_rounded,
                        ),
                        const SizedBox(height: 8),
                        if (_workspace.areas.isEmpty)
                          const _MiniEmptyState(
                            icon: Icons.add_to_queue_rounded,
                            title: 'No apps added yet',
                            message: 'Pick a live window above to build this workspace.',
                          )
                        else
                          for (int i = 0; i < _workspace.areas.length; i++) ...<Widget>[
                            _WorkspaceAreaCard(
                              key: ValueKey<String>(
                                  'area_${i}_${_workspace.areas[i].executable}_${_workspace.areas[i].windowTitle}'),
                              area: _workspace.areas[i],
                              expanded: _expandedAreaIndex == i,
                              onToggleExpanded: () {
                                setState(() => _expandedAreaIndex = _expandedAreaIndex == i ? null : i);
                              },
                              onChanged: (WorkspaceArea updated) => _updateArea(i, updated),
                              onDelete: () => _deleteArea(i),
                              onRefreshGeometry: () => _refreshAreaFromLiveWindow(i),
                            ),
                            const SizedBox(height: 6),
                          ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final Widget content = Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Design.accent.withAlpha(60))),
      ),
      child: Row(
        children: <Widget>[
          _headerIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () {
              if (_dirty) {
                widget.onSave(_workspace.copyWith(
                    name: _nameController.text.trim().isEmpty ? _workspace.name : _nameController.text.trim()));
              }
              widget.onBack();
            },
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Design.accent.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Icon(widget.isNew ? Icons.add_box_rounded : Icons.dashboard_customize_rounded,
                size: 14, color: Design.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Design.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Workspace name',
                hintStyle: TextStyle(fontSize: 13, color: Design.text.withAlpha(90)),
                prefixIcon: Icon(Icons.edit_rounded, size: 15, color: Design.accent),
                filled: true,
                fillColor: Design.text.withAlpha(7),
                contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(18)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(18)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.accent.withAlpha(90)),
                ),
              ),
              onChanged: _renameWorkspace,
            ),
          ),
          const SizedBox(width: 8),
          if (_refreshing)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Design.accent))
          else
            _headerIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh windows', onTap: _loadWindows),
        ],
      ),
    );

    return !user.dragPopupsByIconOnly
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) => windowManager.startDragging(),
            child: content,
          )
        : content;
  }

  Widget _headerIconButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 16, color: Design.accent)),
      ),
    );
  }

  Widget _buildSectionLabel({required String label, required int count, required IconData icon}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
          child: Text('$count',
              style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Design.text.withAlpha(16)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Design.text.withAlpha(6), Design.accent.withAlpha(14)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.grid_view_rounded, size: 14, color: Design.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('PREVIEW',
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Design.text)),
                    const SizedBox(height: 1),
                    Text('Saved windows and their positions',
                        style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(140))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration:
                    BoxDecoration(color: Design.accent.withAlpha(20), borderRadius: BorderRadius.circular(999)),
                child: Text(
                  '${_workspace.areas.length} item${_workspace.areas.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AspectRatio(aspectRatio: 16 / 9, child: _WorkspacePreviewThumbnail(workspace: _workspace)),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 34,
      child: TextField(
        onChanged: (String value) => setState(() => _windowQuery = value),
        style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search open windows',
          hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(90)),
          prefixIcon: Icon(Icons.search_rounded, size: 16, color: Design.accent),
          filled: true,
          fillColor: Design.accent.withAlpha(10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Design.accent.withAlpha(90)),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Editor sub-widgets
// ===========================================================================

class _CurrentWindowTile extends StatefulWidget {
  const _CurrentWindowTile({required this.window, required this.onAdd});

  final Window window;
  final VoidCallback onAdd;

  @override
  State<_CurrentWindowTile> createState() => _CurrentWindowTileState();
}

class _CurrentWindowTileState extends State<_CurrentWindowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Window window = widget.window;
    final int monitorNumber = window.monitor == null ? -1 : Monitor.getMonitorNumber(window.monitor!);
    final String exeName = window.process.exe.isEmpty ? window.process.exePath : window.process.exe;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: _hovered ? Design.accent.withAlpha(18) : Design.text.withAlpha(7),
          border: Border.all(color: _hovered ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onAdd,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: buildExtractedIcon(
                        WindowWatcher.icons[window.hWnd],
                        gaplessPlayback: true,
                        fallback: Icon(Icons.window_rounded, size: 16, color: Design.text.withAlpha(120)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(window.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600, color: Design.text)),
                        const SizedBox(height: 1),
                        Text(exeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (monitorNumber > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration:
                          BoxDecoration(color: Design.accent.withAlpha(18), borderRadius: BorderRadius.circular(999)),
                      child: Text('M$monitorNumber',
                          style: TextStyle(
                              fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.accent)),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.add_rounded, size: 16, color: Design.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceAreaCard extends StatefulWidget {
  const _WorkspaceAreaCard({
    super.key,
    required this.area,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDelete,
    required this.onRefreshGeometry,
  });

  final WorkspaceArea area;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<WorkspaceArea> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onRefreshGeometry;

  @override
  State<_WorkspaceAreaCard> createState() => _WorkspaceAreaCardState();
}

class _WorkspaceAreaCardState extends State<_WorkspaceAreaCard> {
  late final TextEditingController _titleController;
  late final TextEditingController _pathController;
  late final TextEditingController _paramsController;
  late final TextEditingController _hookToController;
  // Geometry is stored as left/top/right/bottom — either monitor-relative
  // fractions (percent mode) or absolute pixels (px mode), per area.usePixels.
  // Edited here as integer position (X/Y) and size (W/H) in the current unit.
  late final TextEditingController _xController;
  late final TextEditingController _yController;
  late final TextEditingController _wController;
  late final TextEditingController _hController;
  late WorkspaceArea _area;

  bool get _usePixels => _area.usePixels;
  String get _unit => _usePixels ? 'px' : '%';

  @override
  void initState() {
    super.initState();
    _area = widget.area.copyWith();
    _titleController = TextEditingController(text: _area.windowTitle);
    _pathController = TextEditingController(text: _area.executable);
    _paramsController = TextEditingController(text: _area.parameters);
    _hookToController = TextEditingController(text: _area.hookTo);
    _xController = TextEditingController(text: _disp(_area.left));
    _yController = TextEditingController(text: _disp(_area.top));
    _wController = TextEditingController(text: _disp(_area.right - _area.left));
    _hController = TextEditingController(text: _disp(_area.bottom - _area.top));
  }

  // A stored value (fraction or px) rendered as the integer shown in its field.
  String _disp(double storageValue) => (_usePixels ? storageValue.round() : (storageValue * 100).round()).toString();

  @override
  void didUpdateWidget(covariant _WorkspaceAreaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare against the controller's current text (not oldWidget). During typing
    // the controller already holds the new value, so no reset fires — assigning
    // `controller.text` would otherwise collapse the selection to offset -1
    // (select-all), making the next keystroke replace the whole field.
    if (widget.area.windowTitle != _titleController.text) _titleController.text = widget.area.windowTitle;
    if (widget.area.executable != _pathController.text) _pathController.text = widget.area.executable;
    if (widget.area.parameters != _paramsController.text) _paramsController.text = widget.area.parameters;
    if (widget.area.hookTo != _hookToController.text) _hookToController.text = widget.area.hookTo;
    final bool px = widget.area.usePixels;
    _syncNum(_xController, widget.area.left, px);
    _syncNum(_yController, widget.area.top, px);
    _syncNum(_wController, widget.area.right - widget.area.left, px);
    _syncNum(_hController, widget.area.bottom - widget.area.top, px);
    _area = widget.area.copyWith();
  }

  // Only rewrite when the underlying value actually changed (e.g. geometry
  // refreshed from a live window or clamped on emit), so typing isn't disrupted.
  void _syncNum(TextEditingController controller, double storageValue, bool px) {
    final int value = px ? storageValue.round() : (storageValue * 100).round();
    if ((int.tryParse(controller.text) ?? -1) != value) controller.text = value.toString();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pathController.dispose();
    _paramsController.dispose();
    _hookToController.dispose();
    _xController.dispose();
    _yController.dispose();
    _wController.dispose();
    _hController.dispose();
    super.dispose();
  }

  void _emit() {
    // Fall back to the current value (not 0) when a field is empty/invalid, so
    // clearing a box to retype doesn't collapse the window's geometry.
    final double left = _numOr(_xController, _area.left);
    final double top = _numOr(_yController, _area.top);
    final double width = _numOr(_wController, _area.right - _area.left);
    final double height = _numOr(_hController, _area.bottom - _area.top);
    final double right = _usePixels ? left + width : (left + width).clamp(0.0, 1.0);
    final double bottom = _usePixels ? top + height : (top + height).clamp(0.0, 1.0);
    widget.onChanged(_area.copyWith(
      windowTitle: _titleController.text,
      executable: _pathController.text,
      parameters: _paramsController.text,
      hookTo: _hookToController.text,
      usePixels: _usePixels,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    ));
  }

  // Reads a field as a stored value (fraction or raw px). Percent mode divides by
  // 100 and clamps to [0, 1]; px mode keeps the raw pixel count.
  double _numOr(TextEditingController controller, double fallback) {
    final double? value = double.tryParse(controller.text.trim());
    if (value == null) return fallback;
    return _usePixels ? value : (value / 100).clamp(0.0, 1.0);
  }

  void _setUnit(bool usePixels) {
    if (_area.usePixels == usePixels) return;
    setState(() {
      _area = _convertAreaMode(_area, usePixels: usePixels);
      _xController.text = _disp(_area.left);
      _yController.text = _disp(_area.top);
      _wController.text = _disp(_area.right - _area.left);
      _hController.text = _disp(_area.bottom - _area.top);
    });
    widget.onChanged(_area.copyWith(
      windowTitle: _titleController.text,
      executable: _pathController.text,
      parameters: _paramsController.text,
      hookTo: _hookToController.text,
    ));
  }

  void _setMonitor(int monitorNumber) {
    setState(() => _area = _area.copyWith(monitorNumber: monitorNumber));
    _emit();
  }

  void _toggleHook(String hook) {
    final List<String> hooks = List<String>.from(_area.hooks);
    if (hooks.contains(hook)) {
      hooks.remove(hook);
    } else {
      hooks.add(hook);
    }
    setState(() => _area = _area.copyWith(hooks: hooks));
    widget.onChanged(_area.copyWith(
      windowTitle: _titleController.text,
      executable: _pathController.text,
      parameters: _paramsController.text,
      hookTo: _hookToController.text,
      hooks: hooks,
    ));
  }

  String _monitorLabel() => widget.area.monitorNumber > 0 ? 'Monitor ${widget.area.monitorNumber}' : 'Monitor auto';

  String _geometryLabel() {
    final WorkspaceArea a = widget.area;
    if (a.usePixels) {
      final int x = a.left.round();
      final int y = a.top.round();
      final int w = (a.right - a.left).round();
      final int h = (a.bottom - a.top).round();
      return '${x}px, ${y}px | ${w}x${h}px';
    }
    final int left = (a.left * 100).round();
    final int top = (a.top * 100).round();
    final int width = ((a.right - a.left) * 100).round();
    final int height = ((a.bottom - a.top) * 100).round();
    return '$left%, $top% | $width%x$height%';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasHookTo = _area.hooks.contains('hook_to');
    final String headerTitle = _titleController.text.isEmpty
        ? (widget.area.executable.split('\\').last.isEmpty ? 'Untitled Window' : widget.area.executable.split('\\').last)
        : _titleController.text;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.expanded ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        color: widget.expanded ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: widget.expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: widget.expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Design.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(headerTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: Design.text)),
                        const SizedBox(height: 1),
                        Text('${_monitorLabel()} | ${_geometryLabel()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
                      ],
                    ),
                  ),
                  _iconButton(
                    icon: Icons.center_focus_strong_rounded,
                    color: Design.accent,
                    tooltip: 'Refresh geometry from live window',
                    onTap: widget.onRefreshGeometry,
                  ),
                  _iconButton(
                    icon: Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                    tooltip: 'Delete app',
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _field(label: 'Window title', controller: _titleController, hint: 'Used for preview and matching'),
                  const SizedBox(height: 8),
                  _field(label: 'Executable path', controller: _pathController, hint: 'C:\\Path\\App.exe'),
                  const SizedBox(height: 8),
                  _field(label: 'Arguments', controller: _paramsController, hint: 'Optional custom arguments'),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('POSITION & SIZE',
                            style: TextStyle(
                                fontSize: Design.baseFontSize,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Design.text.withAlpha(150))),
                      ),
                      _unitToggle(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _usePixels
                        ? 'Fixed pixel size, relative to the monitor top-left'
                        : 'Percent of the monitor, scales with its size',
                    style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(120)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(child: _numField(label: 'X $_unit', controller: _xController)),
                      const SizedBox(width: 6),
                      Expanded(child: _numField(label: 'Y $_unit', controller: _yController)),
                      const SizedBox(width: 6),
                      Expanded(child: _numField(label: 'W $_unit', controller: _wController)),
                      const SizedBox(width: 6),
                      Expanded(child: _numField(label: 'H $_unit', controller: _hController)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _monitorField(),
                  const SizedBox(height: 10),
                  Text('HOOKS',
                      style: TextStyle(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Design.text.withAlpha(150))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String hook in <String>['always_on_top', 'mute', 'hook_to'])
                        _hookChip(hook, _area.hooks.contains(hook)),
                    ],
                  ),
                  if (hasHookTo) ...<Widget>[
                    const SizedBox(height: 8),
                    _field(label: 'Hook to', controller: _hookToController, hint: 'Target exe name, e.g. Code.exe'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 16, color: color)),
      ),
    );
  }

  Widget _hookChip(String hook, bool selected) {
    return InkWell(
      onTap: () => _toggleHook(hook),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Design.accent.withAlpha(24) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(16)),
        ),
        child: Text(
          hook.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: selected ? Design.accent : Design.text.withAlpha(170),
          ),
        ),
      ),
    );
  }

  Widget _field({required String label, required TextEditingController controller, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150))),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Design.text.withAlpha(16)),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(90)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              isDense: true,
            ),
            onChanged: (_) => _emit(),
          ),
        ),
      ],
    );
  }

  Widget _numField({required String label, required TextEditingController controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150))),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Design.text.withAlpha(16)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_usePixels ? 5 : 3),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              isDense: true,
            ),
            onChanged: (_) => _emit(),
          ),
        ),
      ],
    );
  }

  Widget _unitToggle() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _unitOption('%', !_usePixels, () => _setUnit(false)),
        const SizedBox(width: 5),
        _unitOption('px', _usePixels, () => _setUnit(true)),
      ],
    );
  }

  Widget _unitOption(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Design.accent.withAlpha(24) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(16)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w700,
                color: selected ? Design.accent : Design.text.withAlpha(170))),
      ),
    );
  }

  Widget _monitorField() {
    final List<int> numbers = Monitor.monitorIds.values.toSet().toList()..sort();
    final int current = widget.area.monitorNumber;
    final List<DropdownMenuItem<int>> items = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: -1, child: Text('Auto (cursor monitor)')),
      for (final int n in numbers) DropdownMenuItem<int>(value: n, child: Text('Monitor $n')),
      // Keep a disconnected saved monitor selectable so it isn't silently reset.
      if (current > 0 && !numbers.contains(current))
        DropdownMenuItem<int>(value: current, child: Text('Monitor $current')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Monitor', style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Design.text.withAlpha(16)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: current <= 0 ? -1 : current,
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Design.accent),
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text),
              dropdownColor: Theme.of(context).colorScheme.surface,
              items: items,
              onChanged: (int? value) => _setMonitor(value ?? -1),
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// List-mode row + shared preview + empty states
// ===========================================================================

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow({
    super.key,
    required this.workspace,
    required this.onLaunch,
    required this.onEdit,
    required this.onDelete,
  });

  final Workspace workspace;
  final VoidCallback onLaunch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Workspace workspace = widget.workspace;
    final Set<int> monitors =
        workspace.areas.map((WorkspaceArea area) => area.monitorNumber).where((int v) => v > 0).toSet();
    final String meta = '${workspace.areas.length} app${workspace.areas.length == 1 ? '' : 's'}'
        '${monitors.isNotEmpty ? ' | ${monitors.length} monitor${monitors.length == 1 ? '' : 's'}' : ''}';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _hovered ? Design.accent.withAlpha(18) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hovered ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onLaunch,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 74, height: 44, child: _WorkspacePreviewThumbnail(workspace: workspace)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(workspace.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 3, fontWeight: FontWeight.w700, color: Design.text)),
                        const SizedBox(height: 2),
                        Text(meta,
                            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  CancelTraversal(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _rowIconButton(
                          icon: Icons.edit_rounded,
                          color: Design.accent,
                          tooltip: 'Edit',
                          onTap: widget.onEdit,
                        ),
                        _rowIconButton(
                          icon: Icons.delete_outline_rounded,
                          color: _hovered ? Colors.redAccent : Design.text.withAlpha(120),
                          tooltip: 'Delete',
                          onTap: widget.onDelete,
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.play_arrow_rounded, size: 18, color: Design.accent),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 16, color: color)),
      ),
    );
  }
}

class _WorkspacePreviewThumbnail extends StatelessWidget {
  const _WorkspacePreviewThumbnail({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: _WorkspacePreviewPainter(workspace: workspace, accent: Design.accent, text: Design.text),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WorkspacesEmptyState extends StatelessWidget {
  const _WorkspacesEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Design.accent.withAlpha(18)),
              alignment: Alignment.center,
              child: Icon(Icons.dashboard_customize_rounded, size: 26, color: Design.accent.withAlpha(200)),
            ),
            const SizedBox(height: 14),
            Text('No workspaces yet',
                style: TextStyle(fontSize: Design.baseFontSize + 3, fontWeight: FontWeight.w700, color: Design.text)),
            const SizedBox(height: 6),
            Text(
              'Create one, pick live windows, and save their positions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150)),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: onCreate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Design.accent.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.add_rounded, size: 16, color: Design.accent),
                    const SizedBox(width: 6),
                    Text('New Workspace',
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Design.accent)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniEmptyState extends StatelessWidget {
  const _MiniEmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Design.text.withAlpha(7),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 32, color: Design.text.withAlpha(90)),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text)),
          const SizedBox(height: 3),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
        ],
      ),
    );
  }
}

class _WorkspacePreviewPainter extends CustomPainter {
  _WorkspacePreviewPainter({required this.workspace, required this.accent, required this.text});

  final Workspace workspace;
  final Color accent;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect background = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(background, Paint()..color = text.withAlpha(12));

    final Rect innerRect = Rect.fromLTRB(
      size.width * 0.04,
      size.height * 0.06,
      size.width * 0.96,
      size.height * 0.94,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(6)),
      Paint()
        ..color = accent.withAlpha(14)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(6)),
      Paint()
        ..color = text.withAlpha(36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (workspace.areas.isEmpty) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: 'Workspace preview',
          style: TextStyle(color: text.withAlpha(90), fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.8);
      painter.paint(canvas, Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2));
      return;
    }

    for (int i = 0; i < workspace.areas.length; i++) {
      final WorkspaceArea area = workspace.areas[i];
      final Rect rect = _safeRect(innerRect, area);
      if (rect.isEmpty) continue;
      final bool isWide = rect.width >= rect.height;
      final RRect box = RRect.fromRectAndRadius(rect, const Radius.circular(5));

      final int alpha = 40 + (i % 3) * 12;
      canvas.drawRRect(box, Paint()..color = accent.withAlpha(alpha));
      canvas.drawRRect(
        box,
        Paint()
          ..color = accent.withAlpha(120)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      final String title = area.windowTitle.isNotEmpty
          ? area.windowTitle
          : (area.executable.split('\\').isEmpty ? 'Window ${i + 1}' : area.executable.split('\\').last);
      final String monitorText = area.monitorNumber > 0 ? 'M${area.monitorNumber}' : 'Auto';
      final String body = '$monitorText  ${title.length > 24 ? '${title.substring(0, 24)}...' : title}';

      final TextPainter label = TextPainter(
        text: TextSpan(
          text: body,
          style: TextStyle(color: accent.withAlpha(isWide ? 240 : 210), fontSize: 9, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rect.width - 8);
      if (rect.width > 24 && rect.height > 16) label.paint(canvas, Offset(rect.left + 5, rect.top + 4));
    }
  }

  Rect _safeRect(Rect innerRect, WorkspaceArea area) {
    // Previews are laid out in monitor fractions; convert px-mode areas first.
    final WorkspaceArea fractional = area.usePixels ? _convertAreaMode(area, usePixels: false) : area;
    final double left = fractional.left.isFinite ? fractional.left.clamp(0.0, 1.0) : 0.0;
    final double top = fractional.top.isFinite ? fractional.top.clamp(0.0, 1.0) : 0.0;
    final double right = fractional.right.isFinite ? fractional.right.clamp(0.0, 1.0) : 1.0;
    final double bottom = fractional.bottom.isFinite ? fractional.bottom.clamp(0.0, 1.0) : 1.0;

    final double minLeft = left <= right ? left : right;
    final double maxRight = right >= left ? right : left;
    final double minTop = top <= bottom ? top : bottom;
    final double maxBottom = bottom >= top ? bottom : top;

    final double l = innerRect.left + innerRect.width * minLeft;
    final double t = innerRect.top + innerRect.height * minTop;
    final double r = innerRect.left + innerRect.width * maxRight;
    final double b = innerRect.top + innerRect.height * maxBottom;

    if (!<double>[l, t, r, b].every((double v) => v.isFinite)) return Rect.zero;

    final double safeLeft = l <= r ? l : r;
    final double safeRight = r >= l ? r : l;
    final double safeTop = t <= b ? t : b;
    final double safeBottom = b >= t ? b : t;

    return Rect.fromLTRB(safeLeft, safeTop, safeRight, safeBottom);
  }

  @override
  bool shouldRepaint(covariant _WorkspacePreviewPainter oldDelegate) {
    return oldDelegate.workspace != workspace || oldDelegate.accent != accent || oldDelegate.text != text;
  }
}

/// Shared workspace-restore logic, usable outside the [WorkspacesPanel] widget
/// (e.g. from the launcher's `ws` shortcut) without needing panel UI state.
class WorkspaceRunner {
  const WorkspaceRunner._();

  static Future<void> run(Workspace workspace) async {
    await WindowWatcher.fetchWindows();
    final List<Window> initialWindows = List<Window>.from(WindowWatcher.list);
    final Set<int> initialHandles = initialWindows.map((Window window) => window.hWnd).toSet();
    final Map<int, int> areaToWindowHandle = <int, int>{};
    final Set<int> usedHandles = <int>{};
    final List<int> launchQueue = <int>[];

    for (int i = 0; i < workspace.areas.length; i++) {
      final WorkspaceArea area = workspace.areas[i];
      final Window? match = _findMatchingWindow(area, initialWindows, usedHandles);
      if (match != null) {
        areaToWindowHandle[i] = match.hWnd;
        usedHandles.add(match.hWnd);
      } else if (area.executable.isNotEmpty) {
        launchQueue.add(i);
      }
    }

    for (final int index in launchQueue) {
      final WorkspaceArea area = workspace.areas[index];
      _launchArea(area);
    }

    int elapsedMs = 0;
    const int timeoutMs = 9000;
    const int pollIntervalMs = 250;

    while (elapsedMs < timeoutMs &&
        areaToWindowHandle.length < workspace.areas.where((WorkspaceArea a) => a.executable.isNotEmpty).length) {
      await Future<void>.delayed(const Duration(milliseconds: pollIntervalMs));
      elapsedMs += pollIntervalMs;
      await WindowWatcher.fetchWindows();

      final List<Window> currentWindows = WindowWatcher.list;
      final List<Window> newWindows =
          currentWindows.where((Window window) => !initialHandles.contains(window.hWnd)).toList();

      for (int i = 0; i < workspace.areas.length; i++) {
        if (areaToWindowHandle.containsKey(i)) continue;

        final WorkspaceArea area = workspace.areas[i];
        final Window? match = _findMatchingWindow(area, newWindows, usedHandles);
        if (match != null) {
          areaToWindowHandle[i] = match.hWnd;
          usedHandles.add(match.hWnd);
        }
      }
    }

    await WindowWatcher.fetchWindows();
    final List<Window> currentWindows = WindowWatcher.list;

    for (int i = 0; i < workspace.areas.length; i++) {
      final WorkspaceArea area = workspace.areas[i];
      final int? hWnd = areaToWindowHandle[i];
      if (hWnd == null) continue;

      _restoreWindowGeometry(hWnd, area);
      await _applyHooks(area, hWnd, currentWindows);
    }
  }

  static void _launchArea(WorkspaceArea area) {
    WinUtils.open(area.executable, arguments: area.parameters, parseParamaters: true);
  }

  static int _monitorHandleForArea(WorkspaceArea area) {
    int monitorHandle = -1;
    if (area.monitorNumber > 0) {
      for (final MapEntry<int, int> entry in Monitor.monitorIds.entries) {
        if (entry.value == area.monitorNumber) {
          monitorHandle = entry.key;
          break;
        }
      }
    }

    if (monitorHandle == -1) {
      monitorHandle = Monitor.getCursorMonitor();
      if (!Monitor.monitorSizes.containsKey(monitorHandle) && Monitor.monitorSizes.isNotEmpty) {
        monitorHandle = Monitor.monitorSizes.keys.first;
      }
    }

    return monitorHandle;
  }

  static void _restoreWindowGeometry(int hWnd, WorkspaceArea area) {
    final int monitorHandle = _monitorHandleForArea(area);
    final Square? monitorBounds = Monitor.monitorSizes[monitorHandle];
    if (monitorBounds == null || monitorBounds.width <= 0 || monitorBounds.height <= 0) return;

    // Restore a maximized window first, otherwise SetWindowPos is a no-op and the
    // invisible-border reading below reflects the maximized frame, not the target.
    Win32.restoreIfMaximized(hWnd);

    // Everything below is in physical/virtual-screen pixels: `monitorBounds` is
    // the target monitor's physical rect and `getInvisibleBorder` returns physical
    // border widths. Positioning directly in physical coords (instead of routing
    // through setPosDPI's logical→physical guess) keeps the window on the intended
    // monitor even across a mixed-DPI, multi-monitor layout — setPosDPI estimates
    // the target monitor from the window's *current* monitor scale, which lands the
    // window on the wrong monitor when it started on a differently-scaled one.
    final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(hWnd);

    // Windows reports/positions windows by their outer frame, which includes the
    // invisible DWM resize border (~7px on left/right/bottom, 0 on top). Without
    // compensating, a window placed at X/Y = 0 shows a visible gap on the left,
    // right, and bottom while the top sits flush. Offset the position outward and
    // grow the size by the border so the *visible* edges land on the target rect.
    final double zx;
    final double zy;
    final double zw;
    final double zh;
    if (area.usePixels) {
      // Absolute pixels (LTRB), relative to the monitor's top-left.
      final double l = area.left.isFinite ? area.left : 0.0;
      final double t = area.top.isFinite ? area.top : 0.0;
      final double r = area.right.isFinite ? area.right : l;
      final double b = area.bottom.isFinite ? area.bottom : t;
      final double px = l <= r ? l : r;
      final double py = t <= b ? t : b;
      zx = monitorBounds.x + px;
      zy = monitorBounds.y + py;
      zw = (r - l).abs();
      zh = (b - t).abs();
    } else {
      final double leftFrac = area.left.isFinite ? area.left.clamp(0.0, 1.0) : 0.0;
      final double topFrac = area.top.isFinite ? area.top.clamp(0.0, 1.0) : 0.0;
      final double rightFrac = area.right.isFinite ? area.right.clamp(0.0, 1.0) : 1.0;
      final double bottomFrac = area.bottom.isFinite ? area.bottom.clamp(0.0, 1.0) : 1.0;
      final double normalizedLeft = leftFrac <= rightFrac ? leftFrac : rightFrac;
      final double normalizedRight = rightFrac >= leftFrac ? rightFrac : leftFrac;
      final double normalizedTop = topFrac <= bottomFrac ? topFrac : bottomFrac;
      final double normalizedBottom = bottomFrac >= topFrac ? bottomFrac : topFrac;
      zx = monitorBounds.x + monitorBounds.width * normalizedLeft;
      zy = monitorBounds.y + monitorBounds.height * normalizedTop;
      zw = monitorBounds.width * (normalizedRight - normalizedLeft);
      zh = monitorBounds.height * (normalizedBottom - normalizedTop);
    }

    final int left = (zx - border.left).round();
    final int top = (zy - border.top).round();
    final int width = (zw + border.left + border.right).round();
    final int height = (zh + border.top + border.bottom).round();
    if (width <= 0 || height <= 0) return;

    Win32.setPhysicalPos(hWnd, left, top, width, height);
  }

  static Future<void> _applyHooks(WorkspaceArea area, int hWnd, List<Window> currentWindows) async {
    if (area.hooks.contains('always_on_top')) {
      Win32.setAlwaysOnTop(hWnd);
    }

    if (area.hooks.contains('mute')) {
      final List<ProcessVolume>? mixers = await Audio.enumAudioMixer();
      if (mixers != null) {
        for (final ProcessVolume mixer in mixers) {
          if (mixer.processPath == _windowExePathForHandle(hWnd, currentWindows)) {
            Audio.setAudioMixerVolume(mixer.processId, mixer.maxVolume < 0.01 ? 1 : 0.001);
          }
        }
      }
    }

    if (area.hooks.contains('hook_to') && area.hookTo.isNotEmpty) {
      final Window? targetWindow = currentWindows.where((Window window) {
        return window.hWnd != hWnd && window.process.exe.toLowerCase().endsWith(area.hookTo.toLowerCase());
      }).firstOrNull;
      if (targetWindow != null) {
        user.hookedWins[hWnd] ??= <int>[];
        if (!user.hookedWins[hWnd]!.contains(targetWindow.hWnd)) {
          user.hookedWins[hWnd]!.add(targetWindow.hWnd);
        }
      }
    }
  }

  static String _windowExePathForHandle(int hWnd, List<Window> windows) {
    final Window? match = windows.where((Window window) => window.hWnd == hWnd).firstOrNull;
    return match?.process.exePath ?? '';
  }

  static Window? _findMatchingWindow(WorkspaceArea area, List<Window> windows, Set<int> usedHandles) {
    Window? bestMatch;
    int bestScore = -1;

    for (final Window window in windows) {
      if (usedHandles.contains(window.hWnd)) continue;
      if (!_isLikelyMatch(area, window)) continue;

      int score = 0;
      final String areaExe = area.executable.toLowerCase();
      final String windowExe = window.process.exePath.toLowerCase();
      if (windowExe == areaExe) {
        score += 40;
      } else if (windowExe.endsWith(areaExe) || areaExe.endsWith(windowExe)) {
        score += 25;
      }

      final String areaTitle = area.windowTitle.toLowerCase();
      final String windowTitle = window.title.toLowerCase();
      if (areaTitle.isNotEmpty) {
        if (areaTitle == windowTitle) {
          score += 20;
        } else if (areaTitle.contains(windowTitle) || windowTitle.contains(areaTitle)) {
          score += 10;
        }
      }

      if (area.monitorNumber > 0) {
        final int monitorNumber = window.monitor == null ? -1 : Monitor.getMonitorNumber(window.monitor!);
        if (monitorNumber == area.monitorNumber) score += 5;
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = window;
      }
    }

    return bestMatch;
  }

  static bool _isLikelyMatch(WorkspaceArea area, Window window) {
    if (area.executable.isEmpty) return false;

    final String areaExe = area.executable.toLowerCase();
    final String windowExe = window.process.exePath.toLowerCase();

    // Reuse is gated on the executable only. The saved title reflects whatever the
    // window showed at capture time (e.g. "Inbox - Gmail - Chrome") and drifts for
    // browsers/editors, so it must not decide whether an already-open app counts as
    // a match — otherwise we'd relaunch an app that is already running. The title
    // still ranks candidates in _findMatchingWindow when several windows share an exe.
    return windowExe == areaExe ||
        windowExe.endsWith(areaExe) ||
        areaExe.endsWith(windowExe) ||
        window.process.exe.toLowerCase() == areaExe.split('\\').last;
  }
}
