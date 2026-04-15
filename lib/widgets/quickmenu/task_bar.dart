import 'dart:async';
import 'dart:io';
import 'dart:ui';

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
import '../widgets/zoomed_button.dart';

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
    // Determine width for action buttons (play, close, etc.)
    double hoverButtonsWidth = 25;
    final bool hasMediaControls = Boxes.mediaControls.contains(widget.window.process.exe);
    final bool isAudioSource = Caches.audioMixerExes.contains(widget.window.process.exe);

    if (globalSettings.showMediaControlForApp) {
      if (hasMediaControls || isAudioSource) {
        hoverButtonsWidth = 50;
      }
    }

    return SizedBox(
      width: kTaskBarWidth,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Stack(
          children: <Widget>[
            // Background & Main Interaction
            Container(
              width: kTaskBarWidth,
              decoration: BoxDecoration(
                color: (widget.isSelected || _isHovered) ? _hoverColor : Colors.transparent,
                border: widget.isSelected
                    ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))
                    : null,
              ),
              child: _buildMainContent(),
            ),

            // Hover Action Buttons (Right side)
            if (_isHovered)
              Positioned(
                right: 0,
                bottom: 0,
                width: hoverButtonsWidth,
                child: _buildHoverActions(hoverButtonsWidth, hasMediaControls, isAudioSource),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return GestureDetector(
      onTap: _activateWindow,
      onVerticalDragEnd: (_) => _activateWindow(),
      onSecondaryTapUp: (TapUpDetails details) => _showContextMenu(context),
      onLongPress: () => Win32.forceActivateWindow(widget.window.hWnd),
      onHorizontalDragUpdate: (DragUpdateDetails details) => _dragMovement += details.delta.dx,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Wrap(
          spacing: 0,
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            const SizedBox(width: 5),
            _buildIcon(),
            _buildStatusIndicators(),
            _buildTitle(),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final String customIconPath = Globals.getIconRewrite(widget.window.process.exePath, window: widget.window);

    if (customIconPath != "") {
      return Image.file(File(customIconPath), width: 20);
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

    return Transform.translate(
      offset: const Offset(0, 0),
      child: SizedBox(
        width: 5,
        child: Column(
          verticalDirection: VerticalDirection.down,
          children: <Widget>[
            const SizedBox(height: 2),
            const Text("", style: TextStyle(fontSize: 8, height: 1)), // Monitor indicator placeholder
            SizedBox(
              width: 10,
              height: 10,
              child: isPinned
                  ? const Icon(Icons.bookmark, size: 8, color: Colors.grey)
                  : (isActiveAudio ? _buildMuteButton() : const SizedBox()),
            )
          ],
        ),
      ),
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
    // Calculate available width based on hover state
    double maxWidth = _isHovered ? 215 : 240; // Approx logic from original

    return SizedBox(
      width: maxWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          widget.window.title,
          overflow: TextOverflow.fade,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400),
        ),
      ),
    );
  }

  Widget _buildHoverActions(double width, bool hasMedia, bool isAudio) {
    return Container(
      constraints: BoxConstraints(minWidth: width, maxWidth: width, minHeight: kTaskBarItemHeight),
      child: Material(
        type: MaterialType.transparency,
        child: Wrap(
          children: <Widget>[
            if (globalSettings.showMediaControlForApp && (hasMedia || isAudio))
              InkWell(
                hoverColor: _hoverColor,
                onTap: () => WindowWatcher.mediaControl(widget.index),
                child: GestureDetector(
                  onSecondaryTap: () => WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaNexttrack),
                  onTertiaryTapUp: (_) =>
                      WindowWatcher.mediaControl(widget.index, button: AppCommand.mediaPrevioustrack),
                  child: const SizedBox(
                      width: kMediaButtonWidth, height: kTaskBarItemHeight, child: Icon(Icons.play_arrow, size: 15)),
                ),
              ),
            InkWell(
              hoverColor: _hoverColor,
              onTap: () => widget.onClose(widget.index, widget.window),
              onLongPress: () => Win32.closeWindow(widget.window.hWnd, forced: true),
              child: const SizedBox(
                  width: kMediaButtonWidth, height: kTaskBarItemHeight, child: Icon(Icons.close, size: 15)),
            ),
          ],
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
    showModalBottomSheet<void>(
      context: context,
      anchorPoint: const Offset(100, 200),
      elevation: 0,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      enableDrag: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: ContextMenuWidget(hWnd: widget.window.hWnd),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// SEPARATE WIDGET: CONTEXT MENU
// -----------------------------------------------------------------------------

class ContextMenuWidget extends StatefulWidget {
  final int hWnd;
  const ContextMenuWidget({super.key, required this.hWnd});

  @override
  ContextMenuWidgetState createState() => ContextMenuWidgetState();
}

class ContextMenuWidgetState extends State<ContextMenuWidget> {
  late Window window;

  @override
  void initState() {
    super.initState();
    window = Window(widget.hWnd);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: double.infinity,
          width: 280,
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 350),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              colors: <Color>[
                theme.colorScheme.surface,
                theme.colorScheme.surface.withAlpha(globalSettings.themeColors.gradientAlpha),
                theme.colorScheme.surface,
              ],
              stops: const <double>[0, 0.4, 1],
              end: Alignment.bottomRight,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
            ],
            color: theme.colorScheme.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              height: 350,
              child: Theme(
                data: theme.copyWith(
                  hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildHeader(),
                      const Divider(height: 10, thickness: 1),
                      _buildActions(context),
                      const Divider(height: 10, thickness: 1),
                      Expanded(child: _buildFooter(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 30,
          child: WindowWatcher.icons[window.hWnd] != null
              ? Image.memory(WindowWatcher.icons[window.hWnd]!, width: 20, height: 20, gaplessPlayback: true)
              : const Icon(Icons.web_asset_sharp, size: 20),
        ),
        Expanded(
          child: Text(
            window.title,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400,
              fontSize: 16,
              height: 1,
            ),
          ),
        )
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _ContextMenuItem(
                icon: Icons.keyboard_double_arrow_left,
                label: "Left Desktop",
                onTap: () async {
                  await QuickMenuFunctions.toggleQuickMenu(visible: false);
                  Future<void>.delayed(const Duration(milliseconds: 200),
                      () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.left, classMethod: false));
                },
              ),
            ),
            Expanded(
              child: _ContextMenuItem(
                icon: Icons.keyboard_double_arrow_right,
                label: "Right Desktop",
                isRightAligned: true,
                onTap: () async {
                  await QuickMenuFunctions.toggleQuickMenu(visible: false);
                  Future<void>.delayed(const Duration(milliseconds: 200),
                      () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.right, classMethod: false));
                },
              ),
            ),
          ],
        ),
        _ContextMenuItem(
          icon: Icons.pin_end_outlined,
          label: window.isPinned ? "Unpin" : 'Set Always on Top',
          onTap: () {
            Win32.setAlwaysOnTop(window.hWnd);
            Navigator.pop(context);
          },
        ),
        _ContextMenuItem(
          icon: Icons.volume_up_outlined,
          label: "(Un)Mute",
          onTap: () async {
            // Reusing the mute logic
            final List<ProcessVolume>? mixers = await Audio.enumAudioMixer();
            if (mixers != null) {
              for (ProcessVolume m in mixers) {
                if (m.processPath == window.process.exePath) {
                  Audio.setAudioMixerVolume(m.processId, m.maxVolume < 0.01 ? 1 : 0.001);
                }
              }
            }
          },
        ),
        _ContextMenuItem(
          icon: Icons.highlight_off,
          label: "Force Close",
          onTap: () {
            Win32.forceCloseWindowbyProcess(window.process.pId);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("  Hook window with:", style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 5),
              Expanded(
                child: ListView.builder(
                  itemCount: WindowWatcher.list.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Window win = WindowWatcher.list.elementAt(index);
                    if (win.hWnd == widget.hWnd) return const SizedBox();

                    final bool isHooked = (globalSettings.hookedWins[widget.hWnd] ?? <int>[]).contains(win.hWnd);

                    return InkWell(
                      onTap: () {
                        setState(() {
                          globalSettings.hookedWins[widget.hWnd] ??= <int>[];
                          globalSettings.hookedWins[widget.hWnd]!.toggle(win.hWnd);
                          if (globalSettings.hookedWins[widget.hWnd]!.isEmpty) {
                            globalSettings.hookedWins.remove(widget.hWnd);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 25,
                              child: ((WindowWatcher.icons.containsKey(win.hWnd))
                                  ? Image.memory(
                                      WindowWatcher.icons[win.hWnd] ?? Uint8List(0),
                                      width: 16,
                                      height: 16,
                                      gaplessPlayback: true,
                                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                          const Icon(
                                        Icons.check_box_outline_blank,
                                        size: 16,
                                      ),
                                    )
                                  : const Icon(Icons.web_asset_sharp, size: 20)),
                            ), // Simplification for brevity
                            Expanded(child: Text(win.title, maxLines: 1, overflow: TextOverflow.fade)),
                            if (isHooked) const Icon(Icons.phishing, size: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Helper Widget for Context Menu Items
class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isRightAligned;

  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isRightAligned = false,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? iconColor = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: isRightAligned
              ? <Widget>[
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge?.copyWith(height: 1))),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(icon, color: iconColor, size: 18)),
                ]
              : <Widget>[
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(icon, color: iconColor, size: 18)),
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge?.copyWith(height: 1))),
                ],
        ),
      ),
    );
  }
}

// extension ListToggle<T> on List<T> {
//   void toggle(T element) {
//     if (contains(element)) {
//       remove(element);
//     } else {
//       add(element);
//     }
//   }
// }
