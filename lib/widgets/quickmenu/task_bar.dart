import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/music_server.dart';
import '../../models/classes/music_server_manager.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quickmenu_modal.dart';
import '../../models/win32/keys.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';
import '../itzy/quickmenu/button_music_player.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/extracted_icon.dart';
import '../widgets/zoomed_button.dart';
import 'context_menu.dart';
import 'quick_snap_picker.dart';

// --- CONSTANTS ---
const double kTaskBarItemHeight = 28.0;
const double kTaskBarItemExpandedHeight = 42.0;
const double kMediaButtonWidth = 25.0;
const double kTaskBarWidth = 310.0;
const Duration kTimerInterval = Duration(milliseconds: 300);

class Caches {
  static List<int> audioMixer = <int>[];
  static List<String> audioMixerExes = <String>[];
}

class TaskBar extends StatefulWidget {
  const TaskBar({super.key});

  @override
  TaskBarState createState() => TaskBarState();
}

class TaskBarState extends State<TaskBar> with QuickMenuTriggers, TabameListener {
  List<Window> _windows = <Window>[];
  bool _fetching = false;
  bool _keepFetching = true;
  Timer? _mainTimer;
  final ScrollController _scrollController = ScrollController();

  // Window sizing state

  @override
  void initState() {
    super.initState();
    Debug.add("QuickMenu: Taskbar-Init");

    _initializeWindowSize();
    if (mounted) {
      QuickMenuFunctions.addListener(this);
      NativeHooks.addListener(this);
      _fetchWindows();
      _startTimer();
    }
  }

  @override
  Future<void> onQuickActionExecute(String actionName) async {
    if (actionName == "action:refreshTaskbar") {
      await _fetchWindows(force: true);
    }
  }

  int _sizeIncrement = 1;
  void _initializeWindowSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      WidgetsBinding.instance.reassembleApplication();
      // await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      if (!mounted) return;
      final Size size = await WindowManager.instance.getSize();
      await WindowManager.instance.setSize(Size(size.width + _sizeIncrement, size.height + _sizeIncrement));
      _sizeIncrement = _sizeIncrement == 1 ? -1 : 1;
      // await windowManager.setAsFrameless();
    });
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    _mainTimer?.cancel();
    _scrollController.dispose();
    QuickMenuFunctions.removeListener(this);
    NativeHooks.removeListener(this); // Good practice to remove
    super.dispose();
  }

  void _startTimer() {
    _mainTimer = Timer.periodic(kTimerInterval, (Timer timer) {
      if (_keepFetching && !_fetching) {
        if (GetForegroundWindow() != Win32.hWnd && userSettings.hideTabameOnUnfocus && !QuickMenuFunctions.keepOpen) {
          if (DateTime.now().millisecondsSinceEpoch - QuickMenuFunctions.shownTime > 400) {
            QuickMenuFunctions.toggleQuickMenu(visible: false);
          }
        }
        _fetchWindows();
      }
    });
  }

  // --- LOGIC ---

  Future<void> _handleAudio() async {
    final List<ProcessVolume> audioMixer = await Audio.enumAudioMixer() ?? <ProcessVolume>[];

    Caches.audioMixer.clear();
    Caches.audioMixerExes.clear();

    if (audioMixer.isEmpty) return;

    Caches.audioMixer =
        audioMixer.where((ProcessVolume e) => e.peakVolume > 0.005).map((ProcessVolume x) => x.processId).toList();

    Caches.audioMixerExes = audioMixer
        .where((ProcessVolume e) => e.peakVolume > 0.01)
        .map((ProcessVolume x) => x.processPath.split('\\').last)
        .toList();
  }

  Future<void> _fetchWindows({bool force = false, bool updateState = true}) async {
    if (!force && !_keepFetching) return;
    if (_fetching) return;

    if (await WindowWatcher.fetchWindows()) {
      _fetching = true;

      // Update local list
      _windows = List<Window>.from(WindowWatcher.list);

      await _handleAudio();

      if (updateState && mounted) {
        setState(() => _fetching = false);
      } else {
        _fetching = false;
      }
    }
  }

  // --- EVENT LISTENERS ---

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible) {
      _keepFetching = true;
      await _fetchWindows();
    } else {
      _keepFetching = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void onWinEventReceived(int hWnd, WinEventType type) {
    if (type == WinEventType.foreground && !QuickMenuFunctions.isQuickMenuVisible) {
      int parentHWnd = Win32.parent(hWnd);
      if (!_windows.any((Window e) => e.hWnd == parentHWnd)) {
        // Debounce fetch if a new window appears while menu is hidden
        Future<void>.delayed(const Duration(milliseconds: 300), _fetchWindows);
      }
    }
  }

  @override
  void onForegroundWindowChanged(int hWnd) {
    WindowWatcher.hierarchyAdd(hWnd);
  }

  @override
  void onVerticalArrow(bool up) {
    if (_windows.isEmpty) return;
    if (up) {
      if (QuickMenuFunctions.taskBarSelectedIdx > 0) {
        QuickMenuFunctions.taskBarSelectedIdx--;
      } else {
        QuickMenuFunctions.taskBarSelectedIdx = _windows.length - 1;
      }
    } else {
      if (QuickMenuFunctions.taskBarSelectedIdx < _windows.length - 1) {
        QuickMenuFunctions.taskBarSelectedIdx++;
      } else {
        QuickMenuFunctions.taskBarSelectedIdx = 0;
      }
    }
    _scrollToSelected();
    setState(() {});
  }

  void _scrollToSelected() {
    if (QuickMenuFunctions.taskBarSelectedIdx == -1) return;
    final double targetOffset = QuickMenuFunctions.taskBarSelectedIdx * kTaskBarItemHeight;
    // viewportHeight is no longer fixed, using a safe default or checking from context could be better
    // but for now we'll assume a reasonable visible area.
    if (_scrollController.hasClients) {
      final double viewportHeight = _scrollController.position.viewportDimension;
      if (targetOffset < _scrollController.offset) {
        _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
      } else if (targetOffset + kTaskBarItemHeight > _scrollController.offset + viewportHeight) {
        _scrollController.animateTo(targetOffset - viewportHeight + kTaskBarItemHeight + 20,
            duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
      }
    }
  }

  @override
  void onEnter() {
    if (QuickMenuFunctions.taskBarSelectedIdx != -1) {
      if (QuickMenuFunctions.taskBarSelectedIdx < _windows.length) {
        final Window window = _windows[QuickMenuFunctions.taskBarSelectedIdx];
        _activateWindow(window);
        QuickMenuFunctions.resetKeyboardSelection();
      }
    }
  }

  void _activateWindow(Window window) {
    if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
      WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
    }
    Win32.activateWindow(window.hWnd);
    if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
    Globals.lastFocusedWinHWND = window.hWnd;
  }

  // --- UI BUILD ---
  int skipFewBuilds = 5;
  @override
  Widget build(BuildContext context) {
    if (skipFewBuilds > 0) {
      skipFewBuilds--;
    } else {
      skipFewBuilds = 5;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? context = Globals.quickMenuKey.currentContext;
        if (context != null) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          Globals.quickMenuCurrentHeight = box.size.height;
        }
      });
    }
    Globals.heights.taskbar =
        ((userSettings.expandedTaskbar ? kTaskBarItemExpandedHeight : kTaskBarItemHeight) * _windows.length)
            .clamp(150, userSettings.quickMenuDesign == QuickMenuDesigns.matrix.index ? 280 : 320);

    return MouseRegion(
      onEnter: (_) => setState(() => _keepFetching = true),
      child: Container(
        color: Colors.transparent,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: BoxConstraints(
                minHeight: 150, maxHeight: userSettings.quickMenuDesign == QuickMenuDesigns.matrix.index ? 280 : 320),
            child: ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, Colors.transparent, Colors.black],
                  stops: <double>[0.00, 0.93, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstOut,
              child: StreamBuilder<SequenceState?>(
                  stream: MusicServerManager.player.sequenceStateStream,
                  builder: (BuildContext context, AsyncSnapshot<SequenceState?> snapshot) {
                    final SequenceState? sequenceState = snapshot.data;
                    final MusicItem? musicItem = sequenceState?.currentSource?.tag is MusicItem
                        ? sequenceState!.currentSource!.tag as MusicItem
                        : null;

                    int isMusicPlaying = (musicItem != null && userSettings.showMusicPlayerInTaskbar) ? 1 : 0;

                    // return TaskBarMusicItem(item: item);
                    return ListView.builder(
                      shrinkWrap: true,
                      // physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _windows.length + isMusicPlaying,
                      itemBuilder: (BuildContext context, int xIndex) {
                        if (xIndex == 0 && isMusicPlaying != 0) {
                          return TaskBarMusicItem(item: musicItem!);
                        }
                        final int index = xIndex - isMusicPlaying;
                        final Window window = _windows[index];
                        final bool isSelected = index == QuickMenuFunctions.taskBarSelectedIdx;

                        // Add separator if monitor changes
                        if (index > 0 && window.monitor != _windows[index - 1].monitor) {
                          return Column(
                            children: <Widget>[
                              _buildMonitorSeparator(context),
                              TaskBarItem(
                                window: window,
                                index: index,
                                isSelected: isSelected,
                                onClose: _handleWindowClose,
                              ),
                            ],
                          );
                        }

                        // Add padding at bottom
                        if (_windows.length > 10 && index == _windows.length - 1) {
                          return Column(
                            children: <Widget>[
                              TaskBarItem(
                                window: window,
                                index: index,
                                isSelected: isSelected,
                                onClose: _handleWindowClose,
                              ),
                              const SizedBox(height: 20),
                            ],
                          );
                        }

                        return TaskBarItem(
                          window: window,
                          index: index,
                          isSelected: isSelected,
                          onClose: _handleWindowClose,
                        );
                      },
                    );
                  }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonitorSeparator(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Divider(height: 1, color: accent.withAlpha(40)),
    );
  }

  Future<void> _handleWindowClose(int index, Window window) async {
    QuickMenuFunctions.keepOpen = true;
    if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
      WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
    }
    _fetching = true;
    Win32.closeWindow(window.hWnd);

    setState(() {
      _windows.removeAt(index);
    });

    await _handleAudio();
    _fetchWindows();

    if (mounted) setState(() => _fetching = false);
    Future<void>.delayed(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
  }
}

// -----------------------------------------------------------------------------
// SEPARATE WIDGET: TASK BAR ITEM
// -----------------------------------------------------------------------------

class TaskBarItem extends StatefulWidget {
  final Window window;
  final int index;
  final bool isSelected;
  final Function(int index, Window window) onClose;

  const TaskBarItem({
    super.key,
    required this.window,
    required this.index,
    required this.isSelected,
    required this.onClose,
  });

  @override
  State<TaskBarItem> createState() => _TaskBarItemState();
}

class _TaskBarItemState extends State<TaskBarItem> {
  bool _isHovered = false;
  double _dragMovement = 0.0;

  // bool get _isDark => userSettings.themeTypeMode == ThemeType.dark;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    final bool isSelected = widget.isSelected;
    final bool isHovered = _isHovered;
    final bool expanded = userSettings.expandedTaskbar;
    final double height = expanded ? kTaskBarItemExpandedHeight : kTaskBarItemHeight;

    if (userSettings.taskManagerStats && widget.window.process.exe.toLowerCase() == "taskmgr.exe") {
      return const SizedBox.shrink();
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        height: height,
        margin: EdgeInsets.symmetric(horizontal: 4, vertical: expanded ? 2 : 1),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withAlpha(expanded ? 60 : 45)
              : isHovered
                  ? accent.withAlpha(expanded ? 40 : 20)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(expanded ? 8 : 9),
          border: Border.all(
            color: (isSelected && !expanded) ? accent.withAlpha(100) : Colors.transparent,
            width: 1,
          ),
        ),
        child: expanded ? _buildExpandedContent() : _buildMainContent(),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final bool hasMediaControls = Boxes.mediaControls.contains(widget.window.process.exe);
    final bool isAudioSource = Caches.audioMixerExes.contains(widget.window.process.exe);
    final bool highlighted = widget.isSelected || _isHovered;
    final Color accent = userSettings.themeColors.accentColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _activateWindow,
      onVerticalDragEnd: (_) => _activateWindow(),
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context),
      onTertiaryTapUp: (_) => _showZonesPicker(context),
      onLongPress: () => Win32.forceActivateWindow(widget.window.hWnd),
      onHorizontalDragUpdate: (DragUpdateDetails details) => _dragMovement += details.delta.dx,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: highlighted ? 2.5 : 0,
              height: 18,
              margin: EdgeInsets.only(right: highlighted ? 7 : 0),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(
              width: 25,
              height: 24,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  _buildIcon(),
                  Positioned(
                    left: 18,
                    top: 3,
                    child: _buildHelpBadge(),
                  ),
                  if (widget.window.isPinned)
                    Positioned(
                      left: 18,
                      top: 3,
                      child: Icon(Icons.push_pin_rounded, size: 8, color: accent.withAlpha(140)),
                    ),
                  if (Caches.audioMixer.contains(widget.window.process.pId) ||
                      Caches.audioMixer.contains(widget.window.process.mainPID) ||
                      Caches.audioMixerExes.contains(widget.window.process.exe))
                    Positioned(
                      left: 18,
                      bottom: 3,
                      child: _buildMuteButton(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildExpandedTitle()),
            if (_isHovered) ...<Widget>[
              if (userSettings.showMediaControlForApp && (hasMediaControls || isAudioSource)) ...<Widget>[
                _buildVolumeButton(),
                _buildMediaButton()
              ],
              _buildCloseButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedTitle() {
    final Color onSurface = userSettings.themeColors.textColor;
    final bool highlighted = widget.isSelected || _isHovered;
    final String processName = widget.window.process.exe.replaceFirst('.exe', '');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.window.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: highlighted ? onSurface : onSurface.withAlpha(200),
            fontFamily: userSettings.themeColors.entryFontFamily,
            fontStyle: userSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
            fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight(userSettings.themeColors.entryFontWeight),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          processName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: highlighted ? onSurface.withAlpha(170) : onSurface.withAlpha(130),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    final bool hasMediaControls = Boxes.mediaControls.contains(widget.window.process.exe);
    final bool isAudioSource = Caches.audioMixerExes.contains(widget.window.process.exe);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _activateWindow,
      onVerticalDragEnd: (_) => _activateWindow(),
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context),
      onTertiaryTapUp: (_) => _showZonesPicker(context),
      onLongPress: () => Win32.forceActivateWindow(widget.window.hWnd),
      onHorizontalDragUpdate: (DragUpdateDetails details) => _dragMovement += details.delta.dx,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 25,
              height: kTaskBarItemHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  _buildIcon(),
                  Positioned(
                    left: 18,
                    top: 3,
                    child: _buildHelpBadge(),
                  ),
                  if (widget.window.isPinned)
                    Positioned(
                      left: 18,
                      top: 3,
                      child: Icon(Icons.push_pin_rounded,
                          size: 8, color: userSettings.themeColors.accentColor.withAlpha(140)),
                    ),
                  if (Caches.audioMixer.contains(widget.window.process.pId) ||
                      Caches.audioMixer.contains(widget.window.process.mainPID) ||
                      Caches.audioMixerExes.contains(widget.window.process.exe))
                    Positioned(
                      left: 18,
                      bottom: 3,
                      child: _buildMuteButton(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(child: _buildTitle()),
            if (_isHovered) ...<Widget>[
              if (userSettings.showMediaControlForApp && (hasMediaControls || isAudioSource)) _buildMediaButton(),
              if (isAudioSource) _buildVolumeButton(),
              _buildCloseButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton() {
    final Color accent = userSettings.themeColors.accentColor;
    return InkWell(
      hoverColor: accent.withAlpha(40),
      borderRadius: BorderRadius.circular(6),
      onTap: () => _muteWindow(),
      child: SizedBox(
        width: kMediaButtonWidth,
        height: kTaskBarItemHeight,
        child: Icon(Icons.volume_off_outlined, size: 16, color: accent.withAlpha(200)),
      ),
    );
  }

  Widget _buildVolumeButton() {
    final Color accent = userSettings.themeColors.accentColor;
    return InkWell(
      hoverColor: accent.withAlpha(40),
      borderRadius: BorderRadius.circular(6),
      onTap: () => WindowWatcher.mediaControl(widget.index),
      child: GestureDetector(
        onSecondaryTap: () => WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaNexttrack),
        onTertiaryTapUp: (_) => WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaPrevioustrack),
        child: SizedBox(
          width: kMediaButtonWidth,
          height: kTaskBarItemHeight,
          child: Icon(Icons.play_arrow_rounded, size: 16, color: accent.withAlpha(200)),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    final Color accent = userSettings.themeColors.accentColor;
    return Padding(
      padding: EdgeInsets.only(right: !userSettings.expandedTaskbar && WindowWatcher.list.length > 10 ? 5.0 : 0),
      child: InkWell(
        hoverColor: Colors.red.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        onTap: () => widget.onClose(widget.index, widget.window),
        onLongPress: () => Win32.closeWindow(widget.window.hWnd, forced: true),
        child: SizedBox(
          width: kMediaButtonWidth,
          height: kTaskBarItemHeight,
          child: Icon(Icons.close_rounded, size: 16, color: accent.withAlpha(160)),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (Boxes.getIconRewriteByName(widget.window) != "") {
      return Image.asset(
        Boxes.getIconRewriteByName(widget.window),
        width: 20,
        height: 20,
        cacheWidth: 20,
        cacheHeight: 20,
      );
    }
    final String customIconPath = Boxes.getIconRewrite(widget.window.process.exePath);

    if (customIconPath != "") {
      return Image.file(
        File(customIconPath),
        width: 20,
        height: 20,
        cacheWidth: 20,
        cacheHeight: 20,
      );
    }

    if (WindowWatcher.icons.containsKey(widget.window.hWnd)) {
      return buildExtractedIcon(
        WindowWatcher.icons[widget.window.hWnd],
        width: 20,
        height: 20,
        cacheWidth: 20,
        cacheHeight: 20,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Icon(Icons.check_box_outline_blank, size: 20),
        fallback: const Icon(Icons.check_box_outline_blank, size: 20),
      );
    }

    return const SizedBox(
      width: 20,
      child: Icon(Icons.web_asset_sharp, size: 20),
    );
  }

  Widget _buildMuteButton() {
    final Color accent = userSettings.themeColors.accentColor;
    return HoverScaleButton(
      zoom: 1.8,
      onTap: _muteWindow,
      child: Icon(Icons.volume_up_rounded, size: 8, color: accent.withAlpha(180)),
    );
  }

  void _muteWindow() async {
    final List<ProcessVolume>? mixers = await Audio.enumAudioMixer();
    if (mixers == null) return;

    for (ProcessVolume mixer in mixers) {
      if (mixer.processPath == widget.window.process.exePath) {
        double targetVol = mixer.maxVolume < 0.01 ? 1.0 : 0.001;
        Audio.setAudioMixerVolume(mixer.processId, targetVol);
      }
    }
  }

  Widget _buildHelpBadge() {
    if (widget.window.helpText.isEmpty) return const SizedBox.shrink();
    final Color accent = userSettings.themeColors.accentColor;
    return CustomTooltip(
      message: widget.window.helpText,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withAlpha(100),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      widget.window.title,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.3,
        fontFamily: userSettings.theme.entryFontFamily,
        fontStyle: userSettings.theme.entryFontItalic ? FontStyle.italic : FontStyle.normal,
        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight(userSettings.theme.entryFontWeight),
      ),
    );
  }

  void _activateWindow() {
    if (widget.window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
      WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
    }
    Win32.activateWindow(widget.window.hWnd);
    if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
    Globals.lastFocusedWinHWND = widget.window.hWnd;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_dragMovement.abs() < 50) {
      _activateWindow();
      return;
    }
    if (_dragMovement > 0) {
      Win32.moveWindowToDesktop(widget.window.hWnd, DesktopDirection.left);
    } else {
      Win32.moveWindowToDesktop(widget.window.hWnd, DesktopDirection.right);
    }
    _dragMovement = 0.0;
  }

  void _showContextMenu(BuildContext context) {
    showQuickMenuModal(
      context: context,
      maxWidth: 450,
      child: ContextMenuWidget(hWnd: widget.window.hWnd),
    );
  }

  void _showZonesPicker(BuildContext context) {
    showQuickMenuModal(
      context: context,
      maxWidth: 450,
      child: QuickSnapPicker(hWnd: widget.window.hWnd),
    );
  }
}

class TaskBarMusicItem extends StatefulWidget {
  final MusicItem item;
  const TaskBarMusicItem({super.key, required this.item});

  @override
  State<TaskBarMusicItem> createState() => _TaskBarMusicItemState();
}

class _TaskBarMusicItemState extends State<TaskBarMusicItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    final bool expanded = userSettings.expandedTaskbar;
    final double height = expanded ? kTaskBarItemExpandedHeight : kTaskBarItemHeight + 6;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: accent.withAlpha(_isHovered ? 30 : 15),
          borderRadius: BorderRadius.circular(expanded ? 8 : 9),
          border: Border.all(color: accent.withAlpha(20), width: 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: _openMusicPlayer,
                borderRadius: BorderRadius.circular(expanded ? 8 : 9),
                hoverColor: Colors.transparent,
                child: Row(
                  children: <Widget>[
                    _buildCoverArt(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            !expanded
                                ? "${widget.item.artist ?? "Unknown Artist"} - ${widget.item.title}"
                                : widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: userSettings.themeColors.textColor,
                            ),
                          ),
                          !expanded
                              ? const SizedBox.shrink()
                              : Text(
                                  widget.item.artist ?? "Unknown Artist",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: userSettings.themeColors.textColor.withAlpha(160),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverArt() {
    final double size = userSettings.expandedTaskbar ? 32 : 20;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: userSettings.themeColors.accentColor.withAlpha(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.item.localArtworkSmallPath != null && File(widget.item.localArtworkSmallPath!).existsSync()
          ? Image.file(
              File(widget.item.localArtworkSmallPath!),
              fit: BoxFit.cover,
              cacheWidth: 96,
              errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, size: 18),
            )
          : widget.item.coverUrl != null
              ? Image.network(
                  widget.item.coverUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 96,
                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, size: 18),
                )
              : const Icon(Icons.music_note_rounded, size: 18),
    );
  }

  void _openMusicPlayer() {
    unawaited(
      showQuickMenuModal(
        context: context,
        child: const MusicServerPanel(),
      ),
    );
  }

  Widget _buildControls() {
    final Color accent = userSettings.themeColors.accentColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ControlBtn(
          icon: Icons.skip_previous_rounded,
          onTap: () => MusicServerManager.player.seekToPrevious(),
          accent: accent,
        ),
        StreamBuilder<bool>(
          stream: MusicServerManager.player.playingStream,
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            final bool isPlaying = snapshot.data ?? false;
            return _ControlBtn(
              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onTap: () => isPlaying ? MusicServerManager.player.pause() : MusicServerManager.player.play(),
              accent: accent,
              isMain: true,
            );
          },
        ),
        _ControlBtn(
          icon: Icons.skip_next_rounded,
          onTap: () => MusicServerManager.player.seekToNext(),
          accent: accent,
        ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
  final bool isMain;

  const _ControlBtn({
    required this.icon,
    required this.onTap,
    required this.accent,
    this.isMain = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: isMain ? 22 : 18,
          color: accent.withAlpha(200),
        ),
      ),
    );
  }
}
