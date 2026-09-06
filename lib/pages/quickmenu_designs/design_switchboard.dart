import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
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
import '../../widgets/widgets/windows_scroll.dart';
import 'design_backdrop_stable.dart';
import 'design_switchboard_audio.dart';

/// A compact desktop switchboard: window list, an output fader, and a two-row
/// key bank. The existing taskbar owns window actions and keyboard navigation.
class MainMenuSwitchboardWidget extends StatefulWidget {
  const MainMenuSwitchboardWidget({super.key});

  @override
  State<MainMenuSwitchboardWidget> createState() => _MainMenuSwitchboardWidgetState();
}

class _MainMenuSwitchboardWidgetState extends State<MainMenuSwitchboardWidget> {
  final GlobalKey _faderKey = GlobalKey();
  List<Window> _windows = <Window>[];
  int? _monitor;
  bool _loaded = false;
  String _windowSignature = '';

  List<int> get _monitors => _windows.map((Window window) => window.monitor).whereType<int>().toSet().toList()..sort();

  int get _windowCount => _windows.where((Window window) => _monitor == null || window.monitor == _monitor).length;

  void _onWindowsChanged(List<Window> windows) {
    final List<Window> visible = windows
        .where((Window window) => !(user.taskManagerStats && window.process.exe.toLowerCase() == 'taskmgr.exe'))
        .toList(growable: false);
    final String signature = visible.map((Window window) => '${window.hWnd}:${window.monitor}').join('|');
    if (!mounted || (_loaded && signature == _windowSignature)) return;
    setState(() {
      _windows = visible;
      _windowSignature = signature;
      _loaded = true;
      if (_monitor != null && !visible.any((Window window) => window.monitor == _monitor)) {
        _monitor = null;
        QuickMenuFunctions.resetKeyboardSelection();
      }
    });
  }

  void _selectMonitor(int? monitor) {
    if (_monitor == monitor) return;
    QuickMenuFunctions.resetKeyboardSelection();
    setState(() => _monitor = monitor);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double maxHeight = math.max(0, MediaQuery.sizeOf(context).height - 50);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: RepaintBoundary(child: _SwitchboardGround())),
            Theme(
              data: theme.copyWith(
                iconTheme: IconThemeData(size: 16, color: Design.text),
                hoverColor: Design.accent.withAlpha(22),
                focusColor: Design.accent.withAlpha(34),
                splashFactory: NoSplash.splashFactory,
              ),
              child: Material(
                type: MaterialType.transparency,
                textStyle: theme.textTheme.bodyMedium?.copyWith(color: Design.text, fontSize: Design.baseFontSize),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool sideFader = constraints.maxWidth >= 390;
                    final bool showKeyBank = !user.quickActionsAtBottom && !user.bottomBarOnTop;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildHeader(),
                        if (user.bottomBarOnTop) const _SwitchboardShelf(child: PinnedAndTrayList()),
                        Flexible(
                          child: Stack(
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.only(right: sideFader ? 58 : 0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    _buildWorkspaceHeading(),
                                    Flexible(
                                      child: Stack(
                                        children: <Widget>[
                                          RepaintBoundary(
                                            child:
                                                TaskBar(monitorFilter: _monitor, onWindowsChanged: _onWindowsChanged),
                                          ),
                                          // Media sessions can still occupy the list when no windows are open.
                                          if (_loaded &&
                                              _windowCount == 0 &&
                                              !user.mediaSessionsInTaskbar &&
                                              !user.musicPlayerInTaskbar)
                                            Positioned.fill(child: _buildEmptyWorkspace()),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (sideFader)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 58,
                                  child: SwitchboardAudioFader(key: _faderKey, vertical: true),
                                ),
                            ],
                          ),
                        ),
                        if (!sideFader) SwitchboardAudioFader(key: _faderKey, vertical: false),
                        if (!user.bottomBarOnTop) const _SwitchboardShelf(child: PinnedAndTrayList()),
                        if (showKeyBank) const _SwitchboardKeyBank(),
                        if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                        if (user.libreStats) const LibreStats(withTopDivider: false),
                        const _SwitchboardShelf(child: BottomBar()),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: math.max(44, MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 5) + 16),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Design.text.withAlpha(24)))),
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
                  style: TextStyle(fontSize: Design.baseFontSize + 5, fontWeight: FontWeight.w600, letterSpacing: -0.5),
                ),
              ),
            ),
          ),
          if (user.quickActionsAtBottom || user.bottomBarOnTop)
            _SwitchboardControl(
              tooltip: 'Search apps and commands · start typing',
              icon: Icons.search_rounded,
              onTap: () => QuickMenuFunctions.triggerQuickAction('page:launcher'),
            ),
          _SwitchboardControl(
            tooltip: user.hideTabameOnUnfocus ? 'Keep menu open · Ctrl+H' : 'Close on focus loss · Ctrl+H',
            icon: user.hideTabameOnUnfocus ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            selected: !user.hideTabameOnUnfocus,
            onTap: () => setState(() => user.hideTabameOnUnfocus = !user.hideTabameOnUnfocus),
          ),
          const SizedBox(width: 28, height: 28, child: QuickMenuDesignButton()),
          const SizedBox(width: 28, height: 28, child: OpenSettingsButton()),
        ],
      ),
    );
  }

  Widget _buildWorkspaceHeading() {
    final List<int> monitors = _monitors;
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Text('WINDOWS', style: _labelStyle),
            const SizedBox(width: 6),
            Text(
              _loaded ? _windowCount.toString().padLeft(2, '0') : '–',
              style: TextStyle(color: Design.accent, fontSize: Design.baseFontSize, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            if (monitors.length > 1)
              Expanded(
                child: WindowsScrollView(
                  scrollDirection: Axis.horizontal,
                  showScrollbar: false,
                  draggable: true,
                  clipBehavior: Clip.hardEdge,
                  child: Row(
                    children: <Widget>[
                      _monitorButton(label: 'All', monitor: null),
                      for (int index = 0; index < monitors.length; index++)
                        _monitorButton(label: '${index + 1}', monitor: monitors[index]),
                    ],
                  ),
                ),
              )
            else
              Expanded(child: Divider(height: 1, color: Design.text.withAlpha(18))),
          ],
        ),
      ),
    );
  }

  Widget _monitorButton({required String label, required int? monitor}) {
    final bool selected = _monitor == monitor;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: monitor == null ? 'Windows on every display' : 'Windows on display $label',
        child: Semantics(
          selected: selected,
          child: InkWell(
            onTap: () => _selectMonitor(monitor),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 24),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Design.accent.withAlpha(22) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: selected ? Design.accent.withAlpha(90) : Colors.transparent),
              ),
              child: Text(label,
                  style: TextStyle(fontSize: Design.baseFontSize, color: selected ? Design.accent : Design.text)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyWorkspace() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.desktop_windows_outlined, size: 26, color: Design.text.withAlpha(115)),
            const SizedBox(height: 8),
            Text('No windows open', style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => QuickMenuFunctions.triggerQuickAction('page:launcher'),
              child: const Text('Find an app to open'),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle get _labelStyle => TextStyle(
      fontSize: Design.baseFontSize - 1,
      fontWeight: FontWeight.w500,
      letterSpacing: 1,
      color: Design.text.withAlpha(175),
    );

class _SwitchboardGround extends StatelessWidget {
  const _SwitchboardGround();

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
          border: Border.all(color: Design.text.withAlpha(36)),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            if (Design.hasBackdrop) Positioned.fill(child: ColoredBox(color: Design.background.withAlpha(215))),
          ],
        ),
      ),
    );
  }
}

class _SwitchboardShelf extends StatelessWidget {
  const _SwitchboardShelf({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(22)))),
      child: child,
    );
  }
}

class _SwitchboardControl extends StatelessWidget {
  const _SwitchboardControl({required this.tooltip, required this.icon, required this.onTap, this.selected});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: selected,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(icon, size: 16, color: selected == true ? Design.accent : Design.text)),
        ),
      ),
    );
  }
}

class _SwitchboardKeyBank extends StatefulWidget {
  const _SwitchboardKeyBank();

  @override
  State<_SwitchboardKeyBank> createState() => _SwitchboardKeyBankState();
}

class _SwitchboardKeyBankState extends State<_SwitchboardKeyBank> with QuickMenuTriggers {
  final ScrollController _scrollController = ScrollController();
  List<Widget> _actions = <Widget>[];

  @override
  void initState() {
    super.initState();
    _loadActions();
    QuickMenuFunctions.addListener(this);
  }

  void _loadActions() {
    _actions = <Widget>[
      if (kDebugMode) const TestingButton(key: ValueKey<String>('debug')),
      if (user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(key: ValueKey<String>('reminders')),
      for (final String name in Boxes().topBarWidgets.takeWhile((String name) => name != 'Deactivated:'))
        if (quickActionsMap[name]?.isVisible ?? false)
          KeyedSubtree(key: ValueKey<String>(name), child: quickActionsMap[name]!.widget()),
      if (user.lastChangelog != Globals.version) const CheckChangelogButton(key: ValueKey<String>('changelog')),
    ];
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) setState(_loadActions);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Design.background.computeLuminance() < 0.45;
    final Color keySurface = Design.text.withAlpha(dark ? 10 : 7);
    final double keyHeight = math.max(30, MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 1) + 16);
    // final double searchWidth = math.max(76, MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 1) * 5 + 16);

    return Container(
      height: keyHeight * 2 + 20,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(5),
        border: Border(top: BorderSide(color: Design.text.withAlpha(22))),
      ),
      child: _actions.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text('Add your favorite tools in Settings → Quick actions.',
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
            )
          : ScrollbarTheme(
              data: ScrollbarTheme.of(context).copyWith(
                thumbVisibility: const WidgetStatePropertyAll<bool>(true),
                thickness: const WidgetStatePropertyAll<double>(2),
                thumbColor: WidgetStatePropertyAll<Color>(Design.text.withAlpha(65)),
              ),
              child: WindowsScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                showScrollbar: true,
                clipBehavior: Clip.hardEdge,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int index = 0; index < _actions.length; index += 2)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _key(_actions[index], keySurface, keyHeight),
                            if (index + 1 < _actions.length) ...<Widget>[
                              const SizedBox(height: 4),
                              _key(_actions[index + 1], keySurface, keyHeight),
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

  Widget _key(Widget action, Color surface, double height) {
    // Tight constraints expand each existing action's hit target, preserving
    // its tooltip, secondary clicks, and volume-drag gestures.
    return Container(
      width: 32,
      height: height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Design.text.withAlpha(28)),
      ),
      child: action,
    );
  }
}
