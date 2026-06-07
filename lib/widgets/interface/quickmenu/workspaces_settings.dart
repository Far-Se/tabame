import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/windows_scroll.dart';

class WorkspacesSettingsPage extends StatefulWidget {
  const WorkspacesSettingsPage({super.key});

  @override
  State<WorkspacesSettingsPage> createState() => _WorkspacesSettingsPageState();
}

class _WorkspacesSettingsPageState extends State<WorkspacesSettingsPage> {
  late List<Workspace> _workspaces;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _workspaces = List<Workspace>.from(Boxes.workspaces);
  }

  Future<void> _save() async {
    Boxes.workspaces = List<Workspace>.from(_workspaces);
    if (mounted) setState(() {});
  }

  void _addWorkspace() {
    final Workspace workspace = Workspace(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Workspace ${_workspaces.length + 1}',
      areas: <WorkspaceArea>[],
    );
    setState(() {
      _workspaces.add(workspace);
      _editingIndex = _workspaces.length - 1;
    });
    unawaited(_save());
  }

  Future<void> _deleteWorkspace(int index) async {
    final Workspace workspace = _workspaces[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('Delete workspace?'),
          content: Text('Remove "${workspace.name}" and all saved windows from this workspace?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _workspaces.removeAt(index);
      if (_editingIndex == index) {
        _editingIndex = null;
      } else if (_editingIndex != null && _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_editingIndex != null && _editingIndex! < _workspaces.length) {
      return _WorkspaceEditor(
        workspace: _workspaces[_editingIndex!],
        onBack: () => setState(() => _editingIndex = null),
        onSave: (Workspace updated) {
          _workspaces[_editingIndex!] = updated;
          unawaited(_save());
        },
      );
    }

    return _buildDashboard();
  }

  Widget _buildDashboard() {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Workspaces', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'Build app groups from live windows, then relaunch them with saved geometry and hooks',
                      style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _addWorkspace,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Workspace'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: theme.colorScheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _workspaces.isEmpty
              ? _EmptyWorkspaceState(
                  accent: accent,
                  onCreate: _addWorkspace,
                )
              : WindowsScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < _workspaces.length; i++)
                          _WorkspaceListTile(
                            workspace: _workspaces[i],
                            onEdit: () => setState(() => _editingIndex = i),
                            onDelete: () => _deleteWorkspace(i),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _WorkspaceListTile extends StatelessWidget {
  const _WorkspaceListTile({
    required this.workspace,
    required this.onEdit,
    required this.onDelete,
  });

  final Workspace workspace;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    final Set<int> monitors =
        workspace.areas.map((WorkspaceArea area) => area.monitorNumber).where((int v) => v > 0).toSet();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 104,
                height: 62,
                child: _WorkspacePreviewThumbnail(workspace: workspace),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      workspace.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${workspace.areas.length} app${workspace.areas.length == 1 ? '' : 's'}'
                      '${monitors.isNotEmpty ? ' | ${monitors.length} monitor${monitors.length == 1 ? '' : 's'}' : ''}',
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      workspace.areas.isEmpty
                          ? 'Add apps from the live window picker'
                          : 'Uses saved positions, arguments, and hooks',
                      style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_rounded, size: 18, color: accent),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.error),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspacePreviewThumbnail extends StatelessWidget {
  const _WorkspacePreviewThumbnail({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _WorkspacePreviewPainter(
          workspace: workspace,
          accent: accent,
          onSurface: onSurface,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WorkspaceEditor extends StatefulWidget {
  const _WorkspaceEditor({
    required this.workspace,
    required this.onBack,
    required this.onSave,
  });

  final Workspace workspace;
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
  int? _selectedAreaIndex;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace.copyWith();
    _nameController = TextEditingController(text: _workspace.name);
    _selectedAreaIndex = _workspace.areas.isEmpty ? null : 0;
    _initialLoad = _loadWindows();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
    widget.onSave(_workspace);
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
      _workspace.areas = <WorkspaceArea>[
        ..._workspace.areas,
        _captureAreaFromWindow(window),
      ];
      _selectedAreaIndex = _workspace.areas.length - 1;
    });
    widget.onSave(_workspace);
  }

  void _deleteArea(int index) {
    setState(() {
      final List<WorkspaceArea> areas = List<WorkspaceArea>.from(_workspace.areas)..removeAt(index);
      _workspace = _workspace.copyWith(areas: areas);
      if (areas.isEmpty) {
        _selectedAreaIndex = null;
      } else if (_selectedAreaIndex != null && _selectedAreaIndex! >= areas.length) {
        _selectedAreaIndex = areas.length - 1;
      }
    });
    widget.onSave(_workspace);
  }

  void _updateArea(int index, WorkspaceArea updated) {
    setState(() {
      final List<WorkspaceArea> areas = List<WorkspaceArea>.from(_workspace.areas);
      areas[index] = updated;
      _workspace = _workspace.copyWith(areas: areas);
    });
    widget.onSave(_workspace);
  }

  void _refreshAreaFromLiveWindow(int index) {
    final WorkspaceArea area = _workspace.areas[index];
    final Window? match = _findMatchingWindow(area, _windows, <int>{});
    if (match == null) return;
    _updateArea(
        index,
        _captureAreaFromWindow(match).copyWith(
          executable: area.executable,
          parameters: area.parameters,
          hookTo: area.hookTo,
          hooks: List<String>.from(area.hooks),
          windowTitle: area.windowTitle,
        ));
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
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    final String name = _nameController.text.trim().isEmpty ? _workspace.name : _nameController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: 'Back',
                onPressed: () {
                  widget.onSave(_workspace.copyWith(name: name));
                  widget.onBack();
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Workspace name',
                  ),
                  onChanged: _renameWorkspace,
                ),
              ),
              const SizedBox(width: 8),
              if (_refreshing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                )
              else
                IconButton(
                  icon: Icon(Icons.refresh_rounded, size: 18, color: accent),
                  tooltip: 'Refresh windows',
                  onPressed: _loadWindows,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: FutureBuilder<void>(
              future: _initialLoad,
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                return WindowsScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _WorkspacePreviewSection(workspace: _workspace),
                        const SizedBox(height: 16),
                        _sectionHeader(
                          context,
                          title: 'Current Windows',
                          subtitle: 'Pick from the open windows on this machine',
                          trailing: _buildSearchField(context),
                        ),
                        const SizedBox(height: 10),
                        if (_filteredWindows().isEmpty)
                          _EmptyMiniState(
                            icon: Icons.window_rounded,
                            title: _windows.isEmpty ? 'No current windows found' : 'No windows match your search',
                            message: _windows.isEmpty
                                ? 'Open the apps you want to capture, then refresh the list.'
                                : 'Try a different keyword or clear the filter.',
                          )
                        else
                          Column(
                            children: <Widget>[
                              for (final Window window in _filteredWindows()) ...<Widget>[
                                _CurrentWindowTile(
                                  window: window,
                                  accent: accent,
                                  onSurface: onSurface,
                                  onAdd: () => _addWindow(window),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        const SizedBox(height: 8),
                        _sectionHeader(
                          context,
                          title: 'Selected Apps',
                          subtitle: 'Saved windows, arguments, and hooks',
                        ),
                        const SizedBox(height: 10),
                        if (_workspace.areas.isEmpty)
                          const _EmptyMiniState(
                            icon: Icons.dashboard_customize_rounded,
                            title: 'No apps added yet',
                            message: 'Pick a live window above to build this workspace.',
                          )
                        else
                          Column(
                            children: <Widget>[
                              for (int i = 0; i < _workspace.areas.length; i++) ...<Widget>[
                                _WorkspaceAreaCard(
                                  key: ValueKey<String>(
                                      'area_${i}_${_workspace.areas[i].executable}_${_workspace.areas[i].windowTitle}'),
                                  area: _workspace.areas[i],
                                  accent: accent,
                                  onSurface: onSurface,
                                  expanded: _selectedAreaIndex == i,
                                  onToggleExpanded: () {
                                    setState(() {
                                      _selectedAreaIndex = _selectedAreaIndex == i ? null : i;
                                    });
                                  },
                                  onChanged: (WorkspaceArea updated) => _updateArea(i, updated),
                                  onDelete: () => _deleteArea(i),
                                  onRefreshGeometry: () => _refreshAreaFromLiveWindow(i),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
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

  Widget _buildSearchField(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 260,
      height: 36,
      child: TextField(
        onChanged: (String value) => setState(() => _windowQuery = value),
        decoration: InputDecoration(
          hintText: 'Search open windows',
          hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.35)),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: onSurface.withValues(alpha: 0.35)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: onSurface.withValues(alpha: 0.10)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: onSurface.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: userSettings.themeColors.accent.withValues(alpha: 0.35)),
          ),
          filled: true,
          fillColor: onSurface.withValues(alpha: 0.03),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}

class _WorkspacePreviewSection extends StatelessWidget {
  const _WorkspacePreviewSection({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            onSurface.withValues(alpha: 0.03),
            accent.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.dashboard_customize_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Preview',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visual summary of the selected windows and their saved positions',
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              Text(
                '${workspace.areas.length} item${workspace.areas.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _WorkspacePreviewThumbnail(workspace: workspace),
          ),
        ],
      ),
    );
  }
}

class _CurrentWindowTile extends StatelessWidget {
  const _CurrentWindowTile({
    required this.window,
    required this.accent,
    required this.onSurface,
    required this.onAdd,
  });

  final Window window;
  final Color accent;
  final Color onSurface;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final int monitorNumber = window.monitor == null ? -1 : Monitor.getMonitorNumber(window.monitor!);
    final String exeName = window.process.exe.isEmpty ? window.process.exePath : window.process.exe;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: onSurface.withValues(alpha: 0.03),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: buildExtractedIcon(
                    WindowWatcher.icons[window.hWnd],
                    gaplessPlayback: true,
                    fallback: Icon(Icons.window_rounded, size: 18, color: onSurface.withValues(alpha: 0.45)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      window.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (monitorNumber > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'M$monitorNumber',
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.add_rounded, size: 18, color: accent),
            ],
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
    required this.accent,
    required this.onSurface,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDelete,
    required this.onRefreshGeometry,
  });

  final WorkspaceArea area;
  final Color accent;
  final Color onSurface;
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
  late WorkspaceArea _area;

  @override
  void initState() {
    super.initState();
    _area = widget.area.copyWith();
    _titleController = TextEditingController(text: _area.windowTitle);
    _pathController = TextEditingController(text: _area.executable);
    _paramsController = TextEditingController(text: _area.parameters);
    _hookToController = TextEditingController(text: _area.hookTo);
  }

  @override
  void didUpdateWidget(covariant _WorkspaceAreaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.windowTitle != widget.area.windowTitle) _titleController.text = widget.area.windowTitle;
    if (oldWidget.area.executable != widget.area.executable) _pathController.text = widget.area.executable;
    if (oldWidget.area.parameters != widget.area.parameters) _paramsController.text = widget.area.parameters;
    if (oldWidget.area.hookTo != widget.area.hookTo) _hookToController.text = widget.area.hookTo;
    _area = widget.area.copyWith();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pathController.dispose();
    _paramsController.dispose();
    _hookToController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_area.copyWith(
      windowTitle: _titleController.text,
      executable: _pathController.text,
      parameters: _paramsController.text,
      hookTo: _hookToController.text,
    ));
  }

  void _toggleHook(String hook) {
    final List<String> hooks = List<String>.from(_area.hooks);
    if (hooks.contains(hook)) {
      hooks.remove(hook);
    } else {
      hooks.add(hook);
    }
    setState(() {
      _area = _area.copyWith(hooks: hooks);
    });
    widget.onChanged(_area.copyWith(
      windowTitle: _titleController.text,
      executable: _pathController.text,
      parameters: _paramsController.text,
      hookTo: _hookToController.text,
      hooks: hooks,
    ));
  }

  String _monitorLabel() {
    return widget.area.monitorNumber > 0 ? 'Monitor ${widget.area.monitorNumber}' : 'Monitor auto';
  }

  String _geometryLabel() {
    final int left = (widget.area.left * 100).round();
    final int top = (widget.area.top * 100).round();
    final int width = ((widget.area.right - widget.area.left) * 100).round();
    final int height = ((widget.area.bottom - widget.area.top) * 100).round();
    return '$left%, $top% | $width%x$height%';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasHookTo = _area.hooks.contains('hook_to');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.onSurface.withValues(alpha: 0.08)),
        color: widget.onSurface.withValues(alpha: 0.025),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: widget.expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: widget.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _titleController.text.isEmpty
                              ? (widget.area.executable.split('\\').last.isEmpty
                                  ? 'Untitled Window'
                                  : widget.area.executable.split('\\').last)
                              : _titleController.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_monitorLabel()} | ${_geometryLabel()}',
                          style:
                              TextStyle(fontSize: Design.baseFontSize, color: widget.onSurface.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onRefreshGeometry,
                    icon: Icon(Icons.center_focus_strong_rounded, size: 16, color: widget.accent),
                    tooltip: 'Refresh geometry from live window',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: Icon(Icons.delete_outline_rounded, size: 16, color: theme.colorScheme.error),
                    tooltip: 'Delete app',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _field(
                    label: 'Window title',
                    controller: _titleController,
                    hint: 'Used for preview and matching',
                    onChanged: _emit,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    label: 'Executable path',
                    controller: _pathController,
                    hint: 'C:\\Path\\App.exe',
                    onChanged: _emit,
                  ),
                  const SizedBox(height: 8),
                  _field(
                    label: 'Arguments',
                    controller: _paramsController,
                    hint: 'Optional custom arguments',
                    onChanged: _emit,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Hooks',
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        fontWeight: FontWeight.w700,
                        color: widget.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String hook in <String>['always_on_top', 'mute', 'hook_to'])
                        ChoiceChip(
                          label: Text(hook.replaceAll('_', ' ').toUpperCase()),
                          selected: _area.hooks.contains(hook),
                          onSelected: (_) => _toggleHook(hook),
                          labelStyle: TextStyle(
                            fontSize: Design.baseFontSize,
                            fontWeight: FontWeight.w700,
                            color:
                                _area.hooks.contains(hook) ? widget.accent : widget.onSurface.withValues(alpha: 0.75),
                          ),
                          selectedColor: widget.accent.withValues(alpha: 0.15),
                          backgroundColor: widget.onSurface.withValues(alpha: 0.04),
                          side: BorderSide(
                            color: _area.hooks.contains(hook)
                                ? widget.accent.withValues(alpha: 0.35)
                                : widget.onSurface.withValues(alpha: 0.10),
                          ),
                        ),
                    ],
                  ),
                  if (hasHookTo) ...<Widget>[
                    const SizedBox(height: 8),
                    _field(
                      label: 'Hook to',
                      controller: _hookToController,
                      hint: 'Target exe name, for example Code.exe',
                      onChanged: _emit,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onChanged,
  }) {
    final Color onSurface = widget.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onSurface.withValues(alpha: 0.10)),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(fontSize: Design.baseFontSize + 2),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.40)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

class _EmptyWorkspaceState extends StatelessWidget {
  const _EmptyWorkspaceState({
    required this.accent,
    required this.onCreate,
  });

  final Color accent;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.dashboard_customize_rounded, size: 58, color: onSurface.withValues(alpha: 0.20)),
          const SizedBox(height: 16),
          Text(
            'No workspaces created yet',
            style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 8),
          Text(
            'Create one, pick live windows, and save their positions',
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.45)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create Workspace'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMiniState extends StatelessWidget {
  const _EmptyMiniState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: onSurface.withValues(alpha: 0.025),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: onSurface.withValues(alpha: 0.20)),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.65))),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

class _WorkspacePreviewPainter extends CustomPainter {
  _WorkspacePreviewPainter({
    required this.workspace,
    required this.accent,
    required this.onSurface,
  });

  final Workspace workspace;
  final Color accent;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect background = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(
      background,
      Paint()..color = onSurface.withValues(alpha: 0.04),
    );

    final Rect innerRect = Rect.fromLTRB(
      size.width * 0.04,
      size.height * 0.06,
      size.width * 0.96,
      size.height * 0.94,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(10)),
      Paint()
        ..color = accent.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(10)),
      Paint()
        ..color = onSurface.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (workspace.areas.isEmpty) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: 'Workspace preview',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.35),
            fontSize: Design.baseFontSize + 2,
            fontWeight: FontWeight.w600,
          ),
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
      final RRect box = RRect.fromRectAndRadius(rect, const Radius.circular(8));

      final double alpha = 0.15 + (i % 3) * 0.04;
      canvas.drawRRect(
        box,
        Paint()..color = accent.withValues(alpha: alpha),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..color = accent.withValues(alpha: 0.45)
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
          style: TextStyle(
            color: accent.withValues(alpha: isWide ? 0.95 : 0.85),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rect.width - 8);
      label.paint(canvas, Offset(rect.left + 6, rect.top + 5));
    }
  }

  Rect _safeRect(Rect innerRect, WorkspaceArea area) {
    final double left = area.left.isFinite ? area.left.clamp(0.0, 1.0) : 0.0;
    final double top = area.top.isFinite ? area.top.clamp(0.0, 1.0) : 0.0;
    final double right = area.right.isFinite ? area.right.clamp(0.0, 1.0) : 1.0;
    final double bottom = area.bottom.isFinite ? area.bottom.clamp(0.0, 1.0) : 1.0;

    final double minLeft = left <= right ? left : right;
    final double maxRight = right >= left ? right : left;
    final double minTop = top <= bottom ? top : bottom;
    final double maxBottom = bottom >= top ? bottom : top;

    final double l = innerRect.left + innerRect.width * minLeft;
    final double t = innerRect.top + innerRect.height * minTop;
    final double r = innerRect.left + innerRect.width * maxRight;
    final double b = innerRect.top + innerRect.height * maxBottom;

    if (!<double>[l, t, r, b].every((double v) => v.isFinite)) {
      return Rect.zero;
    }

    final double safeLeft = l <= r ? l : r;
    final double safeRight = r >= l ? r : l;
    final double safeTop = t <= b ? t : b;
    final double safeBottom = b >= t ? b : t;

    return Rect.fromLTRB(safeLeft, safeTop, safeRight, safeBottom);
  }

  @override
  bool shouldRepaint(covariant _WorkspacePreviewPainter oldDelegate) {
    return oldDelegate.workspace != workspace || oldDelegate.accent != accent || oldDelegate.onSurface != onSurface;
  }
}
