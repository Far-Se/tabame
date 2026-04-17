import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../../models/win32/keys.dart';
import '../../models/globals.dart';
import '../../models/util/quickmenu_modal.dart';
import '../widgets/zoomed_button.dart';
import 'context_menu.dart';
import 'quick_grid_picker.dart';

// --- CONSTANTS ---
const double kTaskBarItemHeight = 26.4;
const double kMediaButtonWidth = 25.0;
const double kTaskBarWidth = 310.0;
const Duration kTimerInterval = Duration(milliseconds: 300);

class Caches {
  static double lastHeight = 0;
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

  // Audio state
  bool _spotifyWasPaused = false;
  int _spotifyDelayPlay = 0;
  bool _audioJumpOneTick = false;

  // Window sizing state
  bool _justToggled = false;
  int _sizeIncrement = 1;

  @override
  void initState() {
    super.initState();
    Debug.add("QuickMenu: Taskbar-Init");

    // optimize image cache
    // PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;

    if (mounted) {
      QuickMenuFunctions.addListener(this);
      NativeHooks.addListener(this);
      _fetchWindows();
      _startTimer();
      _initializeWindowSize();
    }
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
      if (globalSettings.pauseSpotifyWhenNewSound && !_keepFetching) {
        if (_audioJumpOneTick) {
          _audioJumpOneTick = false;
        } else {
          _handleAudio();
          _audioJumpOneTick = true;
        }
      }

      if (_keepFetching && !_fetching) {
        _fetchWindows();
      }
    });
  }

  void _initializeWindowSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final Size size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width + _sizeIncrement, size.height + _sizeIncrement));
      _sizeIncrement = _sizeIncrement == 1 ? -1 : 1;
    });
  }

  // --- LOGIC ---

  Future<void> _handleHeight() async {
    if (Globals.changingPages == true) return;

    double currentHeight = (_windows.length * kTaskBarItemHeight).clamp(100, 400) + 15;
    Globals.heights.taskbar = currentHeight;

    if (currentHeight != Caches.lastHeight) {
      // Logic for specific toggle scenarios
      if (_justToggled && 1 + 1 == 3) {
        // Note: 1+1==3 is always false in original code, kept for legacy logic preservation if intended
        final double newHeight = Globals.heights.allSummed + 80;
        if (Caches.lastHeight != newHeight && mounted) {
          await windowManager.setSize(Size(300, newHeight));
          Caches.lastHeight = newHeight;
        }
        _justToggled = false;
      }
      Caches.lastHeight = currentHeight;
    }
  }

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

    if (globalSettings.pauseSpotifyWhenNewSound) {
      _manageSpotifyPlayback();
    }
  }

  void _manageSpotifyPlayback() {
    bool hasSpotify = Caches.audioMixerExes.contains("Spotify.exe");
    bool hasOtherAudio = Caches.audioMixerExes.length > 1;

    if (hasOtherAudio && hasSpotify) {
      WindowWatcher.triggerSpotify(button: AppCommand.mediaPause);
      _spotifyWasPaused = true;
    } else if (_spotifyWasPaused && Caches.audioMixerExes.isEmpty) {
      if (_spotifyDelayPlay > 2) {
        WindowWatcher.triggerSpotify(button: AppCommand.mediaPlay);
        _spotifyWasPaused = false;
        _spotifyDelayPlay = 0;
      } else {
        _spotifyDelayPlay++;
      }
    }
  }

  Future<void> _fetchWindows({bool updateState = true}) async {
    if (!_keepFetching || _fetching) return;

    if (await WindowWatcher.fetchWindows()) {
      _fetching = true;

      // Update local list
      _windows = List<Window>.from(WindowWatcher.list);

      await _handleAudio();
      await _handleHeight();

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
      _justToggled = true;
    } else {
      _justToggled = false;
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
    final double viewportHeight = Caches.lastHeight;
    if (targetOffset < _scrollController.offset) {
      _scrollController.animateTo(targetOffset, duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
    } else if (targetOffset + kTaskBarItemHeight > _scrollController.offset + viewportHeight) {
      _scrollController.animateTo(targetOffset - viewportHeight + kTaskBarItemHeight + 20,
          duration: const Duration(milliseconds: 100), curve: Curves.easeIn);
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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _keepFetching = true),
      child: Container(
        color: Colors.transparent,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            height: Caches.lastHeight,
            constraints: const BoxConstraints(minHeight: 100),
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
              child: ListView.builder(
                padding: EdgeInsets.zero,
                controller: _scrollController,
                itemCount: _windows.length,
                itemBuilder: (BuildContext context, int index) {
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonitorSeparator(BuildContext context) {
    final Color hoverColor = globalSettings.themeTypeMode == ThemeType.dark
        ? Colors.white12.withValues(alpha: 0.15)
        : Colors.black12.withValues(alpha: 0.15);

    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.only(bottom: 5),
      decoration:
          BoxDecoration(color: Colors.transparent, border: Border(top: BorderSide(width: 2, color: hoverColor))),
    );
  }

  Future<void> _handleWindowClose(int index, Window window) async {
    if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
      WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
    }
    _fetching = true;
    Win32.closeWindow(window.hWnd);

    setState(() {
      _windows.removeAt(index);
    });

    await _handleAudio();
    await _handleHeight();
    _fetchWindows();

    if (mounted) setState(() => _fetching = false);
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

  bool get _isDark => globalSettings.themeTypeMode == ThemeType.dark;

  Color get _hoverColor => _isDark ? Colors.white12.withValues(alpha: 0.15) : Colors.black12.withValues(alpha: 0.15);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: kTaskBarItemHeight,
        decoration: BoxDecoration(
          color: (widget.isSelected || _isHovered) ? _hoverColor : Colors.transparent,
          border: widget.isSelected
              ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))
              : null,
        ),
        child: _buildMainContent(),
      ),
    );
  }

  Widget _buildMainContent() {
    final bool hasMediaControls = Boxes.mediaControls.contains(widget.window.process.exe);
    final bool isAudioSource = Caches.audioMixerExes.contains(widget.window.process.exe);

    return GestureDetector(
      onTap: _activateWindow,
      onVerticalDragEnd: (_) => _activateWindow(),
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context),
      onTertiaryTapUp: (_) => _showZonesPicker(context),
      onLongPress: () => Win32.forceActivateWindow(widget.window.hWnd),
      onHorizontalDragUpdate: (DragUpdateDetails details) => _dragMovement += details.delta.dx,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                    bottom: 3,
                    child: _buildStatusIndicators(),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildTitle()),
            if (_isHovered) ...<Widget>[
              if (globalSettings.showMediaControlForApp && (hasMediaControls || isAudioSource)) _buildMediaButton(),
              _buildCloseButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton() {
    return InkWell(
      hoverColor: _hoverColor,
      onTap: () => WindowWatcher.mediaControl(widget.index),
      child: GestureDetector(
        onSecondaryTap: () => WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaNexttrack),
        onTertiaryTapUp: (_) => WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaPrevioustrack),
        child: const SizedBox(
          width: kMediaButtonWidth,
          height: kTaskBarItemHeight,
          child: Icon(Icons.play_arrow_rounded, size: 18),
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return InkWell(
      hoverColor: _hoverColor,
      onTap: () => widget.onClose(widget.index, widget.window),
      onLongPress: () => Win32.closeWindow(widget.window.hWnd, forced: true),
      child: const SizedBox(
        width: kMediaButtonWidth,
        height: kTaskBarItemHeight,
        child: Icon(Icons.close_rounded, size: 18),
      ),
    );
  }

  Widget _buildIcon() {
    final String customIconPath = Boxes.getIconRewrite(widget.window.process.exePath, window: widget.window);

    if (customIconPath != "") {
      return Image.file(File(customIconPath), width: 20, height: 20);
    }

    if (WindowWatcher.icons.containsKey(widget.window.hWnd)) {
      return Image.memory(
        WindowWatcher.icons[widget.window.hWnd] ?? Uint8List(0),
        width: 20,
        height: 20,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Icon(Icons.check_box_outline_blank, size: 20),
      );
    }

    return const SizedBox(
      width: 20,
      child: Icon(Icons.web_asset_sharp, size: 20),
    );
  }

  Widget _buildStatusIndicators() {
    final bool isPinned = widget.window.isPinned;
    final bool isActiveAudio = Caches.audioMixer.contains(widget.window.process.pId) ||
        Caches.audioMixer.contains(widget.window.process.mainPID) ||
        Caches.audioMixerExes.contains(widget.window.process.exe);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (isActiveAudio) _buildMuteButton(),
        if (isPinned) const Icon(Icons.push_pin_rounded, size: 8, color: Colors.grey),
      ],
    );
  }

  Widget _buildMuteButton() {
    return HoverScaleButton(
      zoom: 1.8,
      onTap: () async {
        final List<ProcessVolume>? mixers = await Audio.enumAudioMixer();
        if (mixers == null) return;

        for (ProcessVolume mixer in mixers) {
          if (mixer.processPath == widget.window.process.exePath) {
            double targetVol = mixer.maxVolume < 0.01 ? 1.0 : 0.001;
            Audio.setAudioMixerVolume(mixer.processId, targetVol);
          }
        }
      },
      child: const Icon(Icons.volume_up_rounded, size: 8, color: Colors.grey),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        widget.window.title,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400,
          fontSize: 13,
        ),
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
      child: QuickGridsPicker(hWnd: widget.window.hWnd),
    );
  }
}
