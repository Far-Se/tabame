import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';
import '../widgets/extracted_icon.dart';
import '../widgets/panel_header.dart';

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
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: window.title,
          accent: accent,
          icon: Icons.window_rounded,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildSectionHeader("Window Actions", onSurface),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            _ContextMenuTile(
                              icon: Icons.keyboard_double_arrow_left_rounded,
                              label: "Move",
                              accent: accent,
                              onTap: () async {
                                await QuickMenuFunctions.hideQuickMenu();
                                Future<void>.delayed(
                                    const Duration(milliseconds: 200),
                                    () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.left,
                                        classMethod: false));
                              },
                            ),
                            _ContextMenuTile(
                              icon: Icons.volume_up_rounded,
                              label: "Mute",
                              accent: accent,
                              onTap: () async {
                                final List<ProcessVolume>? mixers = await Audio.enumAudioMixer();
                                if (mixers != null) {
                                  for (ProcessVolume m in mixers) {
                                    if (m.processPath == window.process.exePath) {
                                      Audio.setAudioMixerVolume(m.processId, m.maxVolume < 0.01 ? 1 : 0.001);
                                    }
                                  }
                                }
                                setState(() {});
                              },
                            ),
                            _ContextMenuTile(
                              icon: Icons.highlight_off_rounded,
                              label: "Force Close",
                              accent: accent,
                              isDestructive: true,
                              onTap: () {
                                Win32.forceCloseWindowbyProcess(window.process.pId);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            _ContextMenuTile(
                              icon: Icons.keyboard_double_arrow_right_rounded,
                              label: "Move Right",
                              accent: accent,
                              isRightAligned: true,
                              onTap: () async {
                                await QuickMenuFunctions.hideQuickMenu();
                                Future<void>.delayed(
                                    const Duration(milliseconds: 200),
                                    () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.right,
                                        classMethod: false));
                              },
                            ),
                            _ContextMenuTile(
                              icon: window.isPinned ? Icons.pin_end_rounded : Icons.push_pin_outlined,
                              label: window.isPinned ? "Unpin Window" : 'Always on Top',
                              accent: accent,
                              isRightAligned: true,
                              onTap: () {
                                Win32.setAlwaysOnTop(window.hWnd);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildSectionHeader("Hook Window With", onSurface),
                  _buildHookList(accent, onSurface),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: Design.baseFontSize,
          fontWeight: FontWeight.w700,
          color: onSurface.withAlpha(120),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildHookList(Color accent, Color onSurface) {
    final List<Window> windows = WindowWatcher.list.where((Window win) => win.hWnd != widget.hWnd).toList();

    if (windows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          "No other windows open",
          style: TextStyle(
              fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(100), fontStyle: FontStyle.italic),
        ),
      );
    }

    return Column(
      children: <Widget>[
        for (final Window win in windows)
          _HookWindowTile(
            window: win,
            isHooked: (userSettings.hookedWins[widget.hWnd] ?? <int>[]).contains(win.hWnd),
            accent: accent,
            onTap: () {
              setState(() {
                userSettings.hookedWins[widget.hWnd] ??= <int>[];
                userSettings.hookedWins[widget.hWnd]!.toggle(win.hWnd);
                if (userSettings.hookedWins[widget.hWnd]!.isEmpty) {
                  userSettings.hookedWins.remove(widget.hWnd);
                }
              });
            },
          ),
      ],
    );
  }
}

class _ContextMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final bool isDestructive;
  final bool isRightAligned;

  const _ContextMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.isDestructive = false,
    this.isRightAligned = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: isDestructive ? Colors.red.withAlpha(20) : accent.withAlpha(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: <Widget>[
              if (!isRightAligned) ...<Widget>[
                Icon(
                  icon,
                  size: 16,
                  color: isDestructive ? Colors.redAccent : accent.withAlpha(220),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  textAlign: isRightAligned ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDestructive ? Colors.redAccent : onSurface.withAlpha(220),
                  ),
                ),
              ),
              if (isRightAligned) ...<Widget>[
                const SizedBox(width: 10),
                Icon(
                  icon,
                  size: 16,
                  color: isDestructive ? Colors.redAccent : accent.withAlpha(220),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HookWindowTile extends StatelessWidget {
  final Window window;
  final bool isHooked;
  final Color accent;
  final VoidCallback onTap;

  const _HookWindowTile({
    required this.window,
    required this.isHooked,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: accent.withAlpha(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isHooked ? accent.withAlpha(15) : Colors.transparent,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                height: 20,
                child: buildExtractedIcon(
                  WindowWatcher.icons[window.hWnd],
                  gaplessPlayback: true,
                  fallback: Icon(Icons.web_asset_rounded, size: 16, color: onSurface.withAlpha(100)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  window.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: isHooked ? accent : onSurface.withAlpha(200),
                    fontWeight: isHooked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isHooked)
                Icon(
                  Icons.link_rounded,
                  size: 14,
                  color: accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
