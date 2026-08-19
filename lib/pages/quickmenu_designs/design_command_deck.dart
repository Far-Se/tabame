// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quick_action_list.dart';
import '../../models/util/quickmenu_modal.dart';
import '../../models/util/theme_colors.dart';
import '../../models/win32/keys.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../models/win32/window.dart';
import '../../platform/windows/windows_quick_snap_service.dart';
import '../../widgets/itzy/quickmenu/button_changelog.dart';
import '../../widgets/itzy/quickmenu/button_logo_drag.dart';
import '../../widgets/itzy/quickmenu/button_open_settings.dart';
import '../../widgets/itzy/quickmenu/button_persistent_reminders.dart';
import '../../widgets/itzy/quickmenu/button_testing.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/context_menu.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/quick_snap_picker.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import 'design_backdrop_stable.dart';

/// A workspace-first QuickMenu. Commands live on a fixed tool rail while the
/// main surface is organized around the window currently under inspection.
/// The result behaves more like a compact operator console than a stack of
/// independent bars.
class MainMenuCommandDeckWidget extends StatefulWidget {
  const MainMenuCommandDeckWidget({super.key});

  @override
  State<MainMenuCommandDeckWidget> createState() => _MainMenuCommandDeckWidgetState();
}

class _MainMenuCommandDeckWidgetState extends State<MainMenuCommandDeckWidget> {
  List<Window> _windows = <Window>[];
  Window? _focusedWindow;
  Window? _inspectedWindow;
  int? _monitorFilter;
  String _windowSignature = '';

  List<int> get _monitors {
    final List<int> values = <int>[];
    for (final Window window in _windows) {
      final int? monitor = window.monitor;
      if (monitor != null && !values.contains(monitor)) values.add(monitor);
    }
    values.sort();
    return values;
  }

  Window? get _activeWindow {
    final Window? inspected = _inspectedWindow;
    if (inspected != null && (_monitorFilter == null || inspected.monitor == _monitorFilter)) return inspected;

    final Window? focused = _focusedWindow;
    if (focused != null && (_monitorFilter == null || focused.monitor == _monitorFilter)) return focused;

    for (final Window window in _windows) {
      if (_monitorFilter == null || window.monitor == _monitorFilter) return window;
    }
    return null;
  }

  int get _visibleWindowCount => _monitorFilter == null
      ? _windows.length
      : _windows.where((Window window) => window.monitor == _monitorFilter).length;

  void _handleWindowsChanged(List<Window> windows) {
    final List<Window> visible = windows
        .where((Window window) => !(user.taskManagerStats && window.process.exe.toLowerCase() == 'taskmgr.exe'))
        .toList(growable: false);
    final String signature =
        visible.map((Window window) => '${window.hWnd}:${window.monitor}:${window.isPinned}:${window.title}').join('|');
    if (signature == _windowSignature) return;

    Window? focused;
    for (final Window window in visible) {
      if (window.hWnd == Globals.lastFocusedWinHWND) {
        focused = window;
        break;
      }
    }
    focused ??= visible.isEmpty ? null : visible.first;

    Window? inspected;
    if (_inspectedWindow != null) {
      for (final Window window in visible) {
        if (window.hWnd == _inspectedWindow!.hWnd) {
          inspected = window;
          break;
        }
      }
    }

    final Set<int> monitors = visible.map((Window window) => window.monitor).whereType<int>().toSet();
    if (!mounted) return;
    setState(() {
      _windows = visible;
      _focusedWindow = focused;
      _inspectedWindow = inspected;
      _windowSignature = signature;
      if (_monitorFilter != null && !monitors.contains(_monitorFilter)) _monitorFilter = null;
    });
  }

  void _handleWindowHover(Window? window) {
    if (!mounted || _inspectedWindow?.hWnd == window?.hWnd) return;
    setState(() => _inspectedWindow = window);
  }

  void _selectMonitor(int? monitor) {
    if (_monitorFilter == monitor) return;
    QuickMenuFunctions.resetKeyboardSelection();
    setState(() {
      _monitorFilter = monitor;
      _inspectedWindow = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _DeckPalette palette = _DeckPalette.fromTheme();
    final bool showActionRail = !user.quickActionsAtBottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 290,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: RepaintBoundary(child: _DeckGround(palette: palette))),
            Padding(
              padding: EdgeInsets.only(left: showActionRail ? 42 : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DeckHeader(
                    palette: palette,
                    windowCount: _visibleWindowCount,
                    monitors: _monitors,
                    selectedMonitor: _monitorFilter,
                    onMonitorSelected: _selectMonitor,
                  ),
                  if (user.bottomBarOnTop) _DeckUtilityShelf(palette: palette),
                  // _DeckFocusBay(
                  //   palette: palette,
                  //   window: _activeWindow,
                  //   monitors: _monitors,
                  // ),
                  _DeckWorkspace(
                    palette: palette,
                    empty: _visibleWindowCount == 0,
                    monitorFilter: _monitorFilter,
                    onWindowHover: _handleWindowHover,
                    onWindowsChanged: _handleWindowsChanged,
                  ),
                  if (!user.bottomBarOnTop) _DeckUtilityShelf(palette: palette),
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  _DeckFooter(palette: palette),
                ],
              ),
            ),
            if (showActionRail)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 42,
                child: _DeckActionRail(palette: palette),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeckPalette {
  const _DeckPalette({
    required this.background,
    required this.surface,
    required this.raisedSurface,
    required this.workspace,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentInk,
    required this.rule,
    required this.hover,
    required this.isDark,
  });

  factory _DeckPalette.fromTheme() {
    final Color background = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = background.computeLuminance() < 0.45;
    final double gradientStrength = Design.gradientAlpha.clamp(0, 100) / 100;

    return _DeckPalette(
      background: background,
      surface: Color.alphaBlend(text.withValues(alpha: isDark ? 0.045 : 0.035), background),
      raisedSurface: Color.alphaBlend(text.withValues(alpha: isDark ? 0.075 : 0.055), background),
      workspace: Color.alphaBlend(accent.withValues(alpha: 0.025 + gradientStrength * 0.035), background),
      text: text,
      muted: text.withValues(alpha: isDark ? 0.64 : 0.60),
      faint: text.withValues(alpha: isDark ? 0.34 : 0.32),
      accent: accent,
      accentInk: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? const Color(0xFFF3F5EC)
          : const Color(0xFF151713),
      rule: text.withValues(alpha: isDark ? 0.15 : 0.13),
      hover: accent.withValues(alpha: isDark ? 0.15 : 0.10),
      isDark: isDark,
    );
  }

  final Color background;
  final Color surface;
  final Color raisedSurface;
  final Color workspace;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentInk;
  final Color rule;
  final Color hover;
  final bool isDark;
}

class _DeckGround extends StatelessWidget {
  const _DeckGround({required this.palette});

  final _DeckPalette palette;

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        stops: <double>[for (int index = 0; index < points.length; index += 2) points[index]],
        colors: <Color>[
          for (int index = 1; index < points.length; index += 2) Colors.white.withValues(alpha: points[index]),
        ],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(Design.borderRadius),
          border: Border.all(color: palette.rule, width: 0.8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.isDark ? 0.25 : 0.11),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            if (Design.hasBackdrop)
              Positioned.fill(
                child: ColoredBox(color: palette.background.withValues(alpha: palette.isDark ? 0.82 : 0.88)),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DeckGridPainter(color: palette.rule.withValues(alpha: 0.38)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({
    required this.palette,
    required this.windowCount,
    required this.monitors,
    required this.selectedMonitor,
    required this.onMonitorSelected,
  });

  final _DeckPalette palette;
  final int windowCount;
  final List<int> monitors;
  final int? selectedMonitor;
  final ValueChanged<int?> onMonitorSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.raisedSurface,
          border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DragToMoveArea(
                  child: Row(
                    children: <Widget>[
                      Container(width: 7, height: 7, color: palette.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'COMMAND DECK',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            color: palette.text,
                            fontFamily: Design.uiFontFamily,
                            fontSize: Design.baseFontSize + 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        windowCount.toString().padLeft(2, '0'),
                        style: TextStyle(
                          color: palette.accent,
                          fontFamily: Design.uiFontFamily,
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (monitors.length > 1)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _DeckMonitorButton(
                          label: 'ALL',
                          selected: selectedMonitor == null,
                          palette: palette,
                          onTap: () => onMonitorSelected(null),
                        ),
                        for (int index = 0; index < monitors.length; index++)
                          _DeckMonitorButton(
                            label: 'M${index + 1}',
                            selected: selectedMonitor == monitors[index],
                            palette: palette,
                            onTap: () => onMonitorSelected(monitors[index]),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckMonitorButton extends StatelessWidget {
  const _DeckMonitorButton({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _DeckPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: label == 'ALL' ? 'Show windows on every monitor' : 'Filter windows to $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          hoverColor: palette.hover,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: selected ? palette.accent : palette.rule, width: 0.8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? palette.accentInk : palette.muted,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckFocusBay extends StatelessWidget {
  const _DeckFocusBay({required this.palette, required this.window, required this.monitors});

  final _DeckPalette palette;
  final Window? window;
  final List<int> monitors;

  void _activateWindow() {
    final Window? target = window;
    if (target == null) return;
    if (target.process.exe == 'Taskmgr.exe' && !WinUtils.isAdministrator()) {
      WinKeys.send('{#CTRL}{#SHIFT}{ESCAPE}');
    } else {
      Win32.activateWindow(target.hWnd);
    }
    Globals.lastFocusedWinHWND = target.hWnd;
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  void _openSnap(BuildContext context) {
    final Window? target = window;
    if (target == null) return;
    unawaited(
      showQuickMenuModal(
        context: context,
        maxWidth: 450,
        child: QuickSnapPicker(window: WindowsQuickSnapService.fromLegacyWindow(target)),
      ),
    );
  }

  void _openMore(BuildContext context) {
    final Window? target = window;
    if (target == null) return;
    unawaited(
      showQuickMenuModal(
        context: context,
        maxWidth: 450,
        child: ContextMenuWidget(hWnd: target.hWnd),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Window? target = window;
    return SizedBox(
      height: 68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: target == null
            ? _DeckEmptyFocus(palette: palette)
            : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool showLabels = constraints.maxWidth >= 430;
                  final int monitorIndex = target.monitor == null ? -1 : monitors.indexOf(target.monitor!);
                  final String processName =
                      target.process.exe.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');

                  return Row(
                    children: <Widget>[
                      Expanded(
                        child: InkWell(
                          onTap: _activateWindow,
                          hoverColor: palette.hover,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 110),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.025, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                key: ValueKey<int>(target.hWnd),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    target.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.text,
                                      fontFamily: Design.entryFontFamily,
                                      fontSize: Design.baseFontSize + 3,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: <Widget>[
                                      Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: palette.accent,
                                          fontFamily: Design.uiFontFamily,
                                          fontSize: Design.baseFontSize - 2,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Flexible(
                                        child: Text(
                                          monitorIndex < 0 ? processName : '$processName  /  M${monitorIndex + 1}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: palette.muted,
                                            fontFamily: Design.uiFontFamily,
                                            fontSize: Design.baseFontSize - 1,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _DeckWindowAction(
                        label: 'Snap',
                        icon: Icons.grid_view_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        onTap: () => _openSnap(context),
                      ),
                      _DeckWindowAction(
                        label: 'Top',
                        icon: target.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        palette: palette,
                        showLabel: showLabels,
                        active: target.isPinned,
                        onTap: () => Win32.setAlwaysOnTop(target.hWnd),
                      ),
                      _DeckWindowAction(
                        label: 'More',
                        icon: Icons.more_horiz_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        onTap: () => _openMore(context),
                      ),
                      _DeckWindowAction(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        destructive: true,
                        onTap: () => Win32.closeWindow(target.hWnd),
                      ),
                      const SizedBox(width: 5),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _DeckEmptyFocus extends StatelessWidget {
  const _DeckEmptyFocus({required this.palette});

  final _DeckPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: palette.rule),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.layers_clear_rounded, size: 15, color: palette.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Workspace clear',
                  style: TextStyle(
                    color: palette.text,
                    fontFamily: Design.entryFontFamily,
                    fontSize: Design.baseFontSize + 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Open an app or use a command from the rail.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontFamily: Design.uiFontFamily,
                    fontSize: Design.baseFontSize - 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckWindowAction extends StatelessWidget {
  const _DeckWindowAction({
    required this.label,
    required this.icon,
    required this.palette,
    required this.showLabel,
    required this.onTap,
    this.active = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final _DeckPalette palette;
  final bool showLabel;
  final VoidCallback onTap;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color danger = palette.isDark ? const Color(0xFFFF817B) : const Color(0xFFAE332E);
    final Color foreground = destructive ? danger : (active ? palette.accent : palette.muted);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: destructive ? danger.withValues(alpha: 0.12) : palette.hover,
        child: SizedBox(
          width: showLabel ? 48 : 30,
          height: 38,
          child: showLabel
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(icon, size: 15, color: foreground),
                    const SizedBox(height: 2),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: foreground,
                        fontFamily: Design.uiFontFamily,
                        fontSize: Design.baseFontSize - 3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                )
              : Icon(icon, size: 17, color: foreground),
        ),
      ),
    );
  }
}

class _DeckWorkspace extends StatelessWidget {
  const _DeckWorkspace({
    required this.palette,
    required this.empty,
    required this.monitorFilter,
    required this.onWindowHover,
    required this.onWindowsChanged,
  });

  final _DeckPalette palette;
  final bool empty;
  final int? monitorFilter;
  final ValueChanged<Window?> onWindowHover;
  final ValueChanged<List<Window>> onWindowsChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.workspace,
        border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
      ),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 27, right: 3, top: 3, bottom: 3),
            child: RepaintBoundary(
              child: TaskBar(
                monitorFilter: monitorFilter,
                onWindowHover: onWindowHover,
                onWindowsChanged: onWindowsChanged,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 27,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DeckRulerPainter(
                  line: palette.rule,
                  tick: palette.faint,
                  accent: palette.accent,
                ),
              ),
            ),
          ),
          if (empty)
            Positioned(
              left: 54,
              right: 26,
              top: 70,
              child: IgnorePointer(
                child: Text(
                  'NO WINDOWS IN THIS CHANNEL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.faint,
                    fontFamily: Design.uiFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckUtilityShelf extends StatelessWidget {
  const _DeckUtilityShelf({required this.palette});

  final _DeckPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
      ),
      child: const PinnedAndTrayList(),
    );
  }
}

class _DeckFooter extends StatelessWidget {
  const _DeckFooter({required this.palette});

  final _DeckPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.raisedSurface,
          border: Border(top: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: BottomBar(),
        ),
      ),
    );
  }
}

class _DeckActionRail extends StatefulWidget {
  const _DeckActionRail({required this.palette});

  final _DeckPalette palette;

  @override
  State<_DeckActionRail> createState() => _DeckActionRailState();
}

class _DeckActionRailState extends State<_DeckActionRail> with QuickMenuTriggers {
  final ScrollController _scrollController = ScrollController();
  List<Widget> _actions = <Widget>[];

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    _loadActions();
  }

  void _loadActions() {
    _actions = <Widget>[];
    for (final String name in Boxes().topBarWidgets) {
      if (name == 'Deactivated:') break;
      final QuickAction? action = quickActionsMap[name];
      if (action != null && action.isVisible) _actions.add(action.widget());
    }
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Future<void> refreshQuickMenu() async {
    _loadActions();
    if (mounted) setState(() {});
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible && type == QuickMenuPage.quickMenu && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final double target = _scrollController.offset + event.scrollDelta.dy;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = <Widget>[
      if (kDebugMode) const TestingButton(),
      if (user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
      ..._actions,
      if (user.lastChangelog != Globals.version) const CheckChangelogButton(),
    ];

    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: IconThemeData(size: 16, color: widget.palette.text),
        hoverColor: widget.palette.hover,
      ),
      child: SizedBox(
        width: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.palette.raisedSurface,
            border: Border(right: BorderSide(color: widget.palette.rule, width: 0.8)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(
                  height: 38,
                  child: Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: LogoDragButton(),
                  )),
              Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 10), color: widget.palette.accent),
              Expanded(
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: <PointerDeviceKind>{
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.touch,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.unknown,
                      },
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      itemCount: actions.length,
                      itemExtent: 29,
                      itemBuilder: (BuildContext context, int index) => Center(child: actions[index]),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 0.8, color: widget.palette.rule),
              const SizedBox(height: 31, child: Center(child: OpenSettingsButton())),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckGridPainter extends CustomPainter {
  const _DeckGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double x = 18.5; x < size.width; x += 24) {
      for (double y = 18.5; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 0.55, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DeckGridPainter oldDelegate) => oldDelegate.color != color;
}

class _DeckRulerPainter extends CustomPainter {
  const _DeckRulerPainter({required this.line, required this.tick, required this.accent});

  final Color line;
  final Color tick;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = line
      ..strokeWidth = 0.8;
    final Paint tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 0.8;
    final Paint accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 1.4;

    const double axis = 15.5;
    canvas.drawLine(const Offset(axis, 0), Offset(axis, size.height), linePaint);
    int index = 0;
    for (double y = 7.5; y < size.height; y += 12) {
      final bool major = index % 4 == 0;
      canvas.drawLine(Offset(axis - (major ? 7 : 4), y), Offset(axis, y), major ? accentPaint : tickPaint);
      index++;
    }
  }

  @override
  bool shouldRepaint(covariant _DeckRulerPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.tick != tick || oldDelegate.accent != accent;
}
