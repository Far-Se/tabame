// ignore_for_file: unused_element

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quick_action_list.dart';
import '../../models/util/theme_colors.dart';
import '../../models/util/quickmenu_modal.dart';
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
import '../../widgets/widgets/custom_tooltip.dart';
import 'design_backdrop_stable.dart';

/// A mouse-first rundown: configured actions occupy a stable rail, the active
/// window gets a fixed control bay, and monitor filters never reorder targets.
class MainMenuRundownWidget extends StatefulWidget {
  const MainMenuRundownWidget({super.key});

  @override
  State<MainMenuRundownWidget> createState() => _MainMenuRundownWidgetState();
}

class _MainMenuRundownWidgetState extends State<MainMenuRundownWidget> {
  List<Window> _windows = <Window>[];
  Window? _focusedWindow;
  Window? _hoveredWindow;
  int? _monitorFilter;

  Window? get _contextWindow {
    final Window? inspected = _hoveredWindow;
    if (inspected != null && (_monitorFilter == null || inspected.monitor == _monitorFilter)) return inspected;

    final Window? focused = _focusedWindow;
    if (focused != null && (_monitorFilter == null || focused.monitor == _monitorFilter)) return focused;

    for (final Window window in _windows) {
      if (_monitorFilter == null || window.monitor == _monitorFilter) return window;
    }
    return null;
  }

  List<int> get _monitors {
    final List<int> monitors = <int>[];
    for (final Window window in _windows) {
      final int? monitor = window.monitor;
      if (monitor != null && !monitors.contains(monitor)) monitors.add(monitor);
    }
    monitors.sort();
    return monitors;
  }

  void _handleWindowsChanged(List<Window> windows) {
    final List<Window> visibleWindows = windows
        .where((Window window) => !(user.taskManagerStats && window.process.exe.toLowerCase() == 'taskmgr.exe'))
        .toList(growable: false);
    final List<int> monitors = <int>[];
    for (final Window window in visibleWindows) {
      final int? monitor = window.monitor;
      if (monitor != null && !monitors.contains(monitor)) monitors.add(monitor);
    }

    Window? focused;
    for (final Window window in visibleWindows) {
      if (window.hWnd == Globals.lastFocusedWinHWND) {
        focused = window;
        break;
      }
    }
    focused ??= visibleWindows.isEmpty ? null : visibleWindows.first;

    Window? inspected;
    if (_hoveredWindow != null) {
      for (final Window window in visibleWindows) {
        if (window.hWnd == _hoveredWindow!.hWnd) {
          inspected = window;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _windows = visibleWindows;
      _focusedWindow = focused;
      _hoveredWindow = inspected;
      if (_monitorFilter != null && !monitors.contains(_monitorFilter)) _monitorFilter = null;
    });
  }

  void _handleWindowHover(Window? window) {
    if (!mounted || window == null || _hoveredWindow?.hWnd == window.hWnd) return;
    setState(() => _hoveredWindow = window);
  }

  void _selectMonitor(int? monitor) {
    if (_monitorFilter == monitor) return;
    QuickMenuFunctions.resetKeyboardSelection();
    setState(() {
      _monitorFilter = monitor;
      _hoveredWindow = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _RundownPalette palette = _RundownPalette.fromTheme();
    final bool showRail = !user.quickActionsAtBottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 248,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: RepaintBoundary(child: _RundownGround(palette: palette))),
            Padding(
              padding: EdgeInsets.only(left: showRail ? 37 : 0),
              child: _buildMainSurface(palette),
            ),
            if (showRail)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 37,
                child: _RundownActionRail(palette: palette),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSurface(_RundownPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (user.bottomBarOnTop) _RundownSection(palette: palette, child: const PinnedAndTrayList()),
        // _RundownHeader(
        //   palette: palette,
        //   windows: _windows,
        //   monitors: _monitors,
        //   selectedMonitor: _monitorFilter,
        //   onMonitorSelected: _selectMonitor,
        // ),
        // _RundownFocusBay(
        //   palette: palette,
        //   window: _contextWindow,
        //   monitors: _monitors,
        // ),
        RepaintBoundary(
          child: TaskBar(
            monitorFilter: _monitorFilter,
            onWindowHover: _handleWindowHover,
            onWindowsChanged: _handleWindowsChanged,
          ),
        ),
        if (!user.bottomBarOnTop) _RundownSection(palette: palette, child: const PinnedAndTrayList()),
        if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
        if (user.libreStats) const LibreStats(withTopDivider: false),
        _RundownFooter(palette: palette),
      ],
    );
  }
}

class _RundownPalette {
  const _RundownPalette({
    required this.background,
    required this.surface,
    required this.focusSurface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.rule,
    required this.hover,
    required this.isDark,
  });

  factory _RundownPalette.fromTheme() {
    final Color background = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = background.computeLuminance() < 0.45;
    final double intensity = Design.gradientAlpha.clamp(0, 255) / 255;

    return _RundownPalette(
      background: background,
      surface: Color.alphaBlend(text.withValues(alpha: isDark ? 0.055 : 0.035), background),
      focusSurface: Color.alphaBlend(accent.withValues(alpha: 0.055 + (intensity * 0.055)), background),
      text: text,
      muted: text.withValues(alpha: isDark ? 0.62 : 0.58),
      accent: accent,
      rule: text.withValues(alpha: isDark ? 0.16 : 0.14),
      hover: accent.withValues(alpha: isDark ? 0.16 : 0.11),
      isDark: isDark,
    );
  }

  final Color background;
  final Color surface;
  final Color focusSurface;
  final Color text;
  final Color muted;
  final Color accent;
  final Color rule;
  final Color hover;
  final bool isDark;
}

class _RundownGround extends StatelessWidget {
  const _RundownGround({required this.palette});

  final _RundownPalette palette;

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        stops: <double>[for (int i = 0; i < points.length; i += 2) points[i]],
        colors: <Color>[for (int i = 1; i < points.length; i += 2) Colors.white.withValues(alpha: points[i])],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.rule, width: 0.8),
          borderRadius: BorderRadius.circular(Design.borderRadius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.isDark ? 0.22 : 0.10),
              blurRadius: 16,
              spreadRadius: -7,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            if (Design.hasBackdrop)
              Positioned.fill(
                child: ColoredBox(color: palette.background.withValues(alpha: palette.isDark ? 0.78 : 0.84)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RundownActionRail extends StatefulWidget {
  const _RundownActionRail({required this.palette});

  final _RundownPalette palette;

  @override
  State<_RundownActionRail> createState() => _RundownActionRailState();
}

class _RundownActionRailState extends State<_RundownActionRail> with QuickMenuTriggers {
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
    if (visible && _scrollController.hasClients) _scrollController.jumpTo(0);
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.palette.surface,
          border: Border(right: BorderSide(color: widget.palette.rule, width: 0.8)),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 28, child: LogoDragButton()),
            Divider(height: 1, thickness: 0.8, color: widget.palette.rule),
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
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: actions.length,
                    itemExtent: 27,
                    itemBuilder: (BuildContext context, int index) => Center(child: actions[index]),
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 0.8, color: widget.palette.rule),
            const SizedBox(height: 28, child: Center(child: OpenSettingsButton())),
          ],
        ),
      ),
    );
  }
}

class _RundownHeader extends StatelessWidget {
  const _RundownHeader({
    required this.palette,
    required this.windows,
    required this.monitors,
    required this.selectedMonitor,
    required this.onMonitorSelected,
  });

  final _RundownPalette palette;
  final List<Window> windows;
  final List<int> monitors;
  final int? selectedMonitor;
  final ValueChanged<int?> onMonitorSelected;

  int get _visibleCount => selectedMonitor == null
      ? windows.length
      : windows.where((Window window) => window.monitor == selectedMonitor).length;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 29,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DragToMoveArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'WINDOWS  ${_visibleCount.toString().padLeft(2, '0')}',
                      maxLines: 1,
                      style: TextStyle(
                        color: palette.muted,
                        fontFamily: Design.uiFontFamily,
                        fontSize: Design.baseFontSize - 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
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
                        _RundownFilter(
                          label: 'ALL',
                          selected: selectedMonitor == null,
                          palette: palette,
                          onTap: () => onMonitorSelected(null),
                        ),
                        for (int index = 0; index < monitors.length; index++)
                          _RundownFilter(
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

class _RundownFilter extends StatelessWidget {
  const _RundownFilter({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _RundownPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        hoverColor: palette.hover,
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: selected ? palette.accent : palette.rule, width: 0.8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? palette.background : palette.muted,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _RundownFocusBay extends StatelessWidget {
  const _RundownFocusBay({
    required this.palette,
    required this.window,
    required this.monitors,
  });

  final _RundownPalette palette;
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
    showQuickMenuModal(
      context: context,
      maxWidth: 450,
      child: QuickSnapPicker(window: WindowsQuickSnapService.fromLegacyWindow(target)),
    );
  }

  void _openMore(BuildContext context) {
    final Window? target = window;
    if (target == null) return;
    showQuickMenuModal(
      context: context,
      maxWidth: 450,
      child: ContextMenuWidget(hWnd: target.hWnd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Window? target = window;
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.focusSurface,
          border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: target == null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.layers_clear_rounded, size: 17, color: palette.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No open windows · use Launcher for apps and commands',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontFamily: Design.uiFontFamily,
                          fontSize: Design.baseFontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              )
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
                            padding: const EdgeInsets.fromLTRB(10, 5, 8, 4),
                            child: Column(
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
                                    fontSize: Design.baseFontSize + 2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  monitorIndex < 0 ? processName : '$processName  ·  M${monitorIndex + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontFamily: Design.uiFontFamily,
                                    fontSize: Design.baseFontSize - 1,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _RundownContextAction(
                        label: 'SNAP',
                        icon: Icons.grid_view_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        onTap: () => _openSnap(context),
                      ),
                      _RundownContextAction(
                        label: 'TOP',
                        icon: target.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        palette: palette,
                        showLabel: showLabels,
                        active: target.isPinned,
                        onTap: () => Win32.setAlwaysOnTop(target.hWnd),
                      ),
                      _RundownContextAction(
                        label: 'MORE',
                        icon: Icons.more_horiz_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        onTap: () => _openMore(context),
                      ),
                      _RundownContextAction(
                        label: 'CLOSE',
                        icon: Icons.close_rounded,
                        palette: palette,
                        showLabel: showLabels,
                        destructive: true,
                        onTap: () => Win32.closeWindow(target.hWnd),
                      ),
                      const SizedBox(width: 4),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _RundownContextAction extends StatelessWidget {
  const _RundownContextAction({
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
  final _RundownPalette palette;
  final bool showLabel;
  final VoidCallback onTap;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color foreground = destructive ? const Color(0xFFC94A46) : (active ? palette.accent : palette.muted);
    final Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      hoverColor: destructive ? const Color(0xFFC94A46).withValues(alpha: 0.13) : palette.hover,
      child: SizedBox(
        width: showLabel ? 54 : 28,
        height: 32,
        child: showLabel
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontFamily: Design.uiFontFamily,
                      fontSize: Design.baseFontSize - 2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              )
            : Icon(icon, size: 16, color: foreground),
      ),
    );

    return CustomTooltip(message: label.toUpperCaseFirst(), child: button);
  }
}

class _RundownSection extends StatelessWidget {
  const _RundownSection({required this.palette, required this.child});

  final _RundownPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.rule, width: 0.8)),
      ),
      child: child,
    );
  }
}

class _RundownFooter extends StatelessWidget {
  const _RundownFooter({required this.palette});

  final _RundownPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.rule, width: 0.8)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 7),
          child: BottomBar(),
        ),
      ),
    );
  }
}
