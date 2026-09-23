import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../widgets/widgets/glass_surface.dart';
import '../../models/util/quick_action_list.dart';
import '../../models/util/theme_colors.dart';
import '../../models/win32/window.dart';
import '../../widgets/itzy/quickmenu/button_changelog.dart';
import '../../widgets/itzy/quickmenu/button_logo_drag.dart';
import '../../widgets/itzy/quickmenu/button_menu_design.dart';
import '../../widgets/itzy/quickmenu/button_open_settings.dart';
import '../../widgets/itzy/quickmenu/button_persistent_reminders.dart';
import '../../widgets/itzy/quickmenu/button_testing.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
// import '../../widgets/widgets/custom_tooltip.dart';
import '../../widgets/widgets/windows_scroll.dart';
import 'design_backdrop_stable.dart';

void _openLauncher() => QuickMenuFunctions.triggerQuickAction('page:launcher');

/// A radial toolkit beside a short index of its tools. Eight stable positions
/// keep targets predictable; paging changes the bank without rotating buttons.
class MainMenuOrbitWidget extends StatefulWidget {
  const MainMenuOrbitWidget({super.key});

  @override
  State<MainMenuOrbitWidget> createState() => _MainMenuOrbitWidgetState();
}

class _MainMenuOrbitWidgetState extends State<MainMenuOrbitWidget> {
  List<Window> _windows = <Window>[];
  List<int> _monitors = <int>[];
  int? _monitor;
  bool _loaded = false;
  String _signature = '';

  int get _visibleCount => _windows.where((Window window) => _monitor == null || _monitor == window.monitor).length;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(0, MediaQuery.sizeOf(context).height - 50)),
      child: GlassClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: RepaintBoundary(child: _OrbitGround())),
            Theme(
              data: theme.copyWith(
                iconTheme: IconThemeData(size: 16, color: Design.text),
                hoverColor: Design.accent.withAlpha(22),
                focusColor: Design.accent.withAlpha(38),
                splashFactory: NoSplash.splashFactory,
              ),
              child: Material(
                type: MaterialType.transparency,
                textStyle: theme.textTheme.bodyMedium?.copyWith(color: Design.text, fontSize: Design.baseFontSize),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildHeader(),
                    if (!user.quickActionsAtBottom) const _OrbitDock(),
                    if (user.bottomBarOnTop) const _OrbitShelf(child: PinnedAndTrayList(includeQuickActions: false)),
                    _buildWindowHeading(),
                    Flexible(
                      child: Stack(
                        children: <Widget>[
                          RepaintBoundary(child: TaskBar(monitorFilter: _monitor, onWindowsChanged: _onWindowsChanged)),
                          if (_loaded &&
                              _visibleCount == 0 &&
                              !user.mediaSessionsInTaskbar &&
                              !user.musicPlayerInTaskbar)
                            Positioned.fill(
                              child: Center(
                                child: TextButton.icon(
                                  onPressed: _openLauncher,
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  label: const Text('Open an app to get started'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!user.bottomBarOnTop) const _OrbitShelf(child: PinnedAndTrayList(includeQuickActions: false)),
                    if (user.quickActionsAtBottom) const _OrbitDock(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    const _OrbitShelf(
                      child: Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: BottomBar()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: math.max(40, MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 7) + 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 26, height: 28, child: LogoDragButton()),
            const SizedBox(width: 4),
            Expanded(
              child: DragToMoveArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 7, fontWeight: FontWeight.w600, letterSpacing: -0.5),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: user.hideTabameOnUnfocus ? 'Keep menu open · Ctrl+H' : 'Close on focus loss · Ctrl+H',
              child: Semantics(
                label: 'Keep menu open',
                toggled: !user.hideTabameOnUnfocus,
                child: InkWell(
                  onTap: () => setState(() => user.hideTabameOnUnfocus = !user.hideTabameOnUnfocus),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      user.hideTabameOnUnfocus ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                      size: 15,
                      color: user.hideTabameOnUnfocus ? Design.text.withAlpha(175) : Design.accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 28, height: 28, child: QuickMenuDesignButton()),
            const SizedBox(width: 28, height: 28, child: OpenSettingsButton()),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowHeading() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(22)))),
      child: Row(
        children: <Widget>[
          Text('Open windows', style: TextStyle(fontWeight: FontWeight.w500, fontSize: Design.baseFontSize + 1)),
          const SizedBox(width: 6),
          Text(_loaded ? '$_visibleCount' : '–', style: TextStyle(color: Design.accent, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          if (_monitors.length > 1)
            Expanded(
              child: WindowsScrollView(
                scrollDirection: Axis.horizontal,
                showScrollbar: false,
                draggable: true,
                clipBehavior: Clip.hardEdge,
                child: Row(
                  children: <Widget>[
                    _monitorChip('All', null),
                    for (int index = 0; index < _monitors.length; index++)
                      _monitorChip('${index + 1}', _monitors[index]),
                  ],
                ),
              ),
            )
          else
            Expanded(child: Divider(height: 1, color: Design.text.withAlpha(18))),
        ],
      ),
    );
  }

  Widget _monitorChip(String label, int? monitor) {
    final bool selected = monitor == _monitor;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: monitor == null ? 'Windows on all displays' : 'Windows on display $label',
        child: Semantics(
          selected: selected,
          child: InkWell(
            onTap: () => _selectMonitor(monitor),
            customBorder: const StadiumBorder(),
            child: Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: ShapeDecoration(
                shape:
                    StadiumBorder(side: BorderSide(color: selected ? Design.accent.withAlpha(90) : Colors.transparent)),
                color: selected ? Design.accent.withAlpha(20) : Colors.transparent,
              ),
              child: Text(label, style: TextStyle(color: selected ? Design.accent : Design.text)),
            ),
          ),
        ),
      ),
    );
  }

  void _onWindowsChanged(List<Window> windows) {
    final List<Window> visible = windows
        .where((Window window) => !(user.taskManagerStats && window.process.exe.toLowerCase() == 'taskmgr.exe'))
        .toList(growable: false);
    final String signature = visible.map((Window window) => '${window.hWnd}:${window.monitor}').join('|');
    if (!mounted || (_loaded && _signature == signature)) return;
    setState(() {
      _windows = visible;
      _signature = signature;
      _loaded = true;
      _monitors = visible.map((Window window) => window.monitor).whereType<int>().toSet().toList()..sort();
      if (_monitor != null && !_monitors.contains(_monitor)) {
        _monitor = null;
        QuickMenuFunctions.resetKeyboardSelection();
      }
    });
  }

  void _selectMonitor(int? monitor) {
    if (monitor == _monitor) return;
    QuickMenuFunctions.resetKeyboardSelection();
    setState(() => _monitor = monitor);
  }
}

class _OrbitAction {
  final String id;

  final String label;
  final Widget child;
  const _OrbitAction({required this.id, required this.label, required this.child});
}

class _OrbitDialPainter extends CustomPainter {
  final double radius;

  final int slotCount;
  final int? hoveredSlot;
  final Color accent;
  final Color ink;
  const _OrbitDialPainter(
      {required this.radius,
      required this.slotCount,
      required this.hoveredSlot,
      required this.accent,
      required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    paint.color = ink.withAlpha(25);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, 34, paint);
    for (int slot = 0; slot < 8; slot++) {
      final double angle = -math.pi / 2 + slot * math.pi / 4;
      paint.color = slot == hoveredSlot ? accent.withAlpha(200) : ink.withAlpha(slot < slotCount ? 55 : 18);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius + 18), angle - 0.17, 0.34, false, paint);
      if (slot >= slotCount) {
        canvas.drawCircle(
            center + Offset(math.cos(angle), math.sin(angle)) * radius, 2, Paint()..color = ink.withAlpha(40));
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitDialPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      slotCount != oldDelegate.slotCount ||
      hoveredSlot != oldDelegate.hoveredSlot ||
      accent != oldDelegate.accent ||
      ink != oldDelegate.ink;
}

class _OrbitDock extends StatefulWidget {
  const _OrbitDock();

  @override
  State<_OrbitDock> createState() => _OrbitDockState();
}

class _OrbitDockState extends State<_OrbitDock> with QuickMenuTriggers {
  static const int _bankSize = 8;
  static const double _diameter = 156;
  static const double _radius = 57;
  List<_OrbitAction> _actions = <_OrbitAction>[];
  int _page = 0;
  int? _hovered;
  double _wheelDelta = 0;
  int _lastWheelChange = 0;

  int get _pageCount => math.max(1, (_actions.length / _bankSize).ceil());
  int get _pageEnd => math.min((_page + 1) * _bankSize, _actions.length);

  @override
  Widget build(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final double titleHeight = scaler.scale(Design.baseFontSize + 4) * 2.3;
    final double labelHeight = scaler.scale(Design.baseFontSize - 2) * 1.2;
    final double subtitleHeight = scaler.scale(Design.baseFontSize) * 2.5;
    final double height = math.max(172, labelHeight + titleHeight + subtitleHeight + (_pageCount > 1 ? 76 : 36));
    final int? hovered = _hovered;
    final String title = hovered == null ? 'Quick tools' : _actions[hovered].label;
    final String subtitle = _actions.isEmpty
        ? 'Add tools in Settings → Quick actions.'
        : _pageCount > 1
            ? 'Scroll here to browse your tools.'
            : 'Point to a tool to see its name.';

    return Listener(
      onPointerSignal: _onPointerSignal,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 14, 8),
          child: Row(
            children: <Widget>[
              _buildDial(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      _actions.isEmpty ? 'YOUR TOOLKIT' : 'TOOLS ${_page * _bankSize + 1}–$_pageEnd',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize - 2,
                          height: 1.2,
                          letterSpacing: 1.1,
                          color: Design.text.withAlpha(175)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: titleHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 4,
                              fontWeight: FontWeight.w500,
                              height: 1.1,
                              color: hovered == null ? Design.text : Design.accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: Design.baseFontSize, height: 1.25, color: Design.text.withAlpha(185))),
                    if (_pageCount > 1) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          _OrbitPageButton(previous: true, onTap: _page == 0 ? null : () => _changePage(_page - 1)),
                          Expanded(
                            child: Text(
                              '${_page + 1} / $_pageCount',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(185)),
                            ),
                          ),
                          _OrbitPageButton(
                              previous: false, onTap: _page + 1 == _pageCount ? null : () => _changePage(_page + 1)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadActions();
    QuickMenuFunctions.addListener(this);
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (!visible && mounted) setState(() => _hovered = null);
    _wheelDelta = 0;
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) setState(_loadActions);
  }

  Widget _buildDial() {
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OrbitDialPainter(
                  radius: _radius,
                  slotCount: _pageEnd - _page * _bankSize,
                  hoveredSlot: _hovered == null ? null : _hovered! % _bankSize,
                  accent: Design.accent,
                  ink: Design.text,
                ),
              ),
            ),
          ),
          // Hidden banks stay mounted so their action listeners, timers and
          // alternate gestures retain the same lifecycle as the standard bar.
          IndexedStack(
            index: _page,
            sizing: StackFit.expand,
            children: <Widget>[
              for (int page = 0; page < _pageCount; page++)
                ExcludeFocus(
                  excluding: page != _page,
                  child: TickerMode(
                    enabled: page == _page,
                    child: Stack(
                      children: <Widget>[
                        for (int slot = 0; slot < _bankSize && page * _bankSize + slot < _actions.length; slot++)
                          _positionedAction(page * _bankSize + slot, slot),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Semantics(
            button: true,
            label: 'Search apps and commands',
            child: InkWell(
              onTap: _openLauncher,
              customBorder: const CircleBorder(),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Design.accent.withAlpha(22),
                  border: Border.all(color: Design.accent.withAlpha(100)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.search_rounded, size: 21, color: Design.accent),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Search',
                            style: TextStyle(
                                fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w500, color: Design.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _changePage(int page) {
    final int next = page.clamp(0, _pageCount - 1);
    if (next == _page) return;
    setState(() {
      _page = next;
      _hovered = null;
    });
  }

  void _loadActions() {
    _actions = <_OrbitAction>[];
    for (final String name in Boxes().topBarWidgets) {
      if (name == 'Deactivated:') break;
      final QuickAction? action = quickActionsMap[name];
      if (action == null || !action.isVisible) continue;
      final String label = action.name ??
          name
              .replaceAll('Button', '')
              .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (Match match) => '${match[1]} ${match[2]}')
              .trim();
      _actions.add(_OrbitAction(id: name, label: label, child: action.widget()));
    }
    if (user.persistentReminders.isNotEmpty) {
      _actions.add(const _OrbitAction(id: 'orbit-reminders', label: 'Reminders', child: PersistentRemindersWidget()));
    }
    if (user.lastChangelog != Globals.version) {
      _actions.add(const _OrbitAction(id: 'orbit-changelog', label: 'What’s new', child: CheckChangelogButton()));
    }
    if (kDebugMode) {
      _actions.add(const _OrbitAction(id: 'orbit-debug', label: 'Developer tools', child: TestingButton()));
    }
    _page = _page.clamp(0, _pageCount - 1);
    _hovered = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    // Buttons retain their own wheel behavior. Browse from the ring's gaps or
    // its adjacent label area, where the gesture cannot change a tool's value.
    if (event is! PointerScrollEvent || _pageCount < 2 || _hovered != null) return;
    final double delta = event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent _) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastWheelChange < 160) return;
      _wheelDelta += delta;
      if (_wheelDelta.abs() < 30) return;
      _changePage(_page + (_wheelDelta > 0 ? 1 : -1));
      _wheelDelta = 0;
      _lastWheelChange = now;
    });
  }

  Widget _positionedAction(int index, int slot) {
    final _OrbitAction action = _actions[index];
    final double angle = -math.pi / 2 + slot * math.pi / 4;
    final bool hovered = _hovered == index;
    return Positioned(
      key: ValueKey<String>(action.id),
      left: _diameter / 2 + math.cos(angle) * _radius - 15,
      top: _diameter / 2 + math.sin(angle) * _radius - 15,
      width: 30,
      height: 30,
      child: Semantics(
        label: action.label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = index),
          onExit: (_) {
            if (_hovered == index) setState(() => _hovered = null);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(Design.accent.withAlpha(hovered ? 34 : 8), Design.background),
              border: Border.all(color: hovered ? Design.accent.withAlpha(155) : Design.text.withAlpha(38)),
            ),
            child: ClipOval(child: action.child),
          ),
        ),
      ),
    );
  }
}

class _OrbitGround extends StatelessWidget {
  const _OrbitGround();

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
          for (int index = 1; index < points.length; index += 2) Design.text.withValues(alpha: points[index])
        ],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Design.background,
          borderRadius: BorderRadius.circular(Design.borderRadius),
          border: Border.all(color: Design.accent.withAlpha(55)),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            if (Design.hasBackdrop) Positioned.fill(child: ColoredBox(color: Design.background.withAlpha(220))),
          ],
        ),
      ),
    );
  }
}

class _OrbitPageButton extends StatelessWidget {
  final bool previous;

  final VoidCallback? onTap;
  const _OrbitPageButton({required this.previous, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: previous ? 'Previous tools' : 'Next tools',
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: previous ? 'Previous tools' : 'Next tools',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Design.text.withAlpha(onTap == null ? 18 : 55)),
            ),
            child: Icon(previous ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                size: 14, color: Design.text.withAlpha(onTap == null ? 70 : 220)),
          ),
        ),
      ),
    );
  }
}

class _OrbitShelf extends StatelessWidget {
  final Widget child;

  const _OrbitShelf({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(22)))),
      child: child,
    );
  }
}
