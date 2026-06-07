import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/mixed.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
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

  List<Workspace> get _workspaces => Boxes.workspaces;

  Future<void> _launchWorkspace(Workspace workspace) async {
    if (_isLaunching) return;

    setState(() {
      _isLaunching = true;
      _launchStatus = 'Launching ${workspace.name}...';
    });

    try {
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
          final Window? match = _findMatchingWindow(
            area,
            newWindows,
            usedHandles,
          );
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

  void _launchArea(WorkspaceArea area) {
    WinUtils.open(area.executable, arguments: area.parameters, parseParamaters: true);
  }

  void _restoreWindowGeometry(int hWnd, WorkspaceArea area) {
    final Square? monitorBounds = _monitorBoundsForArea(area);
    if (monitorBounds == null || monitorBounds.width <= 0 || monitorBounds.height <= 0) return;

    final double leftFrac = area.left.isFinite ? area.left.clamp(0.0, 1.0) : 0.0;
    final double topFrac = area.top.isFinite ? area.top.clamp(0.0, 1.0) : 0.0;
    final double rightFrac = area.right.isFinite ? area.right.clamp(0.0, 1.0) : 1.0;
    final double bottomFrac = area.bottom.isFinite ? area.bottom.clamp(0.0, 1.0) : 1.0;
    final double normalizedLeft = leftFrac <= rightFrac ? leftFrac : rightFrac;
    final double normalizedRight = rightFrac >= leftFrac ? rightFrac : leftFrac;
    final double normalizedTop = topFrac <= bottomFrac ? topFrac : bottomFrac;
    final double normalizedBottom = bottomFrac >= topFrac ? bottomFrac : topFrac;

    final int left = (monitorBounds.x + (monitorBounds.width * normalizedLeft)).round();
    final int top = (monitorBounds.y + (monitorBounds.height * normalizedTop)).round();
    final int right = (monitorBounds.x + (monitorBounds.width * normalizedRight)).round();
    final int bottom = (monitorBounds.y + (monitorBounds.height * normalizedBottom)).round();
    final int width = right - left;
    final int height = bottom - top;
    if (width <= 0 || height <= 0) return;

    Win32.setPosDPI(hWnd, PointXY(X: left, Y: top), logicalWidth: width, logicalHeight: height);
  }

  Future<void> _applyHooks(WorkspaceArea area, int hWnd, List<Window> currentWindows) async {
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
        userSettings.hookedWins[hWnd] ??= <int>[];
        if (!userSettings.hookedWins[hWnd]!.contains(targetWindow.hWnd)) {
          userSettings.hookedWins[hWnd]!.add(targetWindow.hWnd);
        }
      }
    }
  }

  String _windowExePathForHandle(int hWnd, List<Window> windows) {
    final Window? match = windows.where((Window window) => window.hWnd == hWnd).firstOrNull;
    return match?.process.exePath ?? '';
  }

  Square? _monitorBoundsForArea(WorkspaceArea area) {
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

    return Monitor.monitorSizes[monitorHandle];
  }

  Window? _findMatchingWindow(WorkspaceArea area, List<Window> windows, Set<int> usedHandles) {
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

  bool _isLikelyMatch(WorkspaceArea area, Window window) {
    if (area.executable.isEmpty) return false;

    final String areaExe = area.executable.toLowerCase();
    final String windowExe = window.process.exePath.toLowerCase();
    final String windowTitle = window.title.toLowerCase();
    final String areaTitle = area.windowTitle.toLowerCase();

    final bool exeMatch = windowExe == areaExe ||
        windowExe.endsWith(areaExe) ||
        areaExe.endsWith(windowExe) ||
        window.process.exe.toLowerCase() == areaExe.split('\\').last;
    if (!exeMatch) return false;

    if (areaTitle.isEmpty) return true;
    return windowTitle.contains(areaTitle) || areaTitle.contains(windowTitle);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Workspaces',
          accent: accent,
          icon: Icons.dashboard_customize_rounded,
        ),
        const SizedBox(height: 8),
        if (_isLaunching)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(color: accent),
                    const SizedBox(height: 16),
                    Text(_launchStatus, style: TextStyle(color: onSurface)),
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
                  ? _EmptyState(accent: accent)
                  : WindowsScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final Workspace workspace in _workspaces)
                            _WorkspaceTile(
                              workspace: workspace,
                              accent: accent,
                              onSurface: onSurface,
                              onTap: () => _launchWorkspace(workspace),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.dashboard_customize_rounded, size: 48, color: onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              'No Workspaces Created',
              style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.60)),
            ),
            const SizedBox(height: 8),
            Text(
              'Create them in QuickMenu Settings',
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.45)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final Workspace workspace;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.widgets_rounded, size: 20, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      workspace.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workspace.areas.length} App${workspace.areas.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.60)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}
