import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/tray_watcher.dart';
import '../../../models/util/quick_action_list.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class QuickMenuSettingsButton extends StatelessWidget {
  const QuickMenuSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: "QuickMenu Settings",
      child: SizedBox(
        width: 25,
        child: IconButton(
          padding: EdgeInsets.zero,
          splashRadius: 25,
          icon: const Icon(Icons.tune_rounded),
          onPressed: () {
            showQuickMenuModal(
              context: context,
              heightFactor: 0.92,
              backdropFilter: false,
              child: const _QMSettingsPanel(),
            );
          },
        ),
      ),
    );
  }
}

// ── Panel ────────────────────────────────────────────────────────────────────

class _QMSettingsPanel extends StatefulWidget {
  const _QMSettingsPanel();

  @override
  State<_QMSettingsPanel> createState() => _QMSettingsPanelState();
}

class _QMSettingsPanelState extends State<_QMSettingsPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<(IconData, String)> _tabs = <(IconData, String)>[
    (Icons.tune_rounded, "Behavior"),
    (Icons.compress_rounded, "Taskbar"),
    (Icons.widgets_outlined, "Bottom Bar"),
    (Icons.grid_view_rounded, "Quick Actions"),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(
          icon: Icons.tune_rounded,
          title: "QUICKMENU SETTINGS",
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.tab,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: _tabs
              .map((final (IconData, String) t) => Tab(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(t.$1, size: 14),
                        const SizedBox(width: 6),
                        Text(t.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const <Widget>[
              _BehaviorTab(),
              _TaskbarTab(),
              _BottomBarTab(),
              _QuickActionsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _toggle({
  required BuildContext context,
  required String title,
  required String subtitle,
  required bool value,
  required Future<void> Function(bool) onChanged,
}) {
  final ThemeData theme = Theme.of(context);
  return InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    color: theme.hintColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          MiniToggleSwitch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: theme.colorScheme.primary,
          ),
        ],
      ),
    ),
  );
}

Widget _sectionLabel(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: Design.baseFontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
    ),
  );
}

// ── Behavior Tab ──────────────────────────────────────────────────────────────

class _BehaviorTab extends StatefulWidget {
  const _BehaviorTab();

  @override
  State<_BehaviorTab> createState() => _BehaviorTabState();
}

class _BehaviorTabState extends State<_BehaviorTab> {
  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            _toggle(
              context: context,
              title: "Hide when losing focus",
              subtitle: "Close Tabame when clicking external windows",
              value: user.hideTabameOnUnfocus,
              onChanged: (bool v) async {
                user.hideTabameOnUnfocus = v;
                await Boxes.updateSettings("hideTabameOnUnfocus", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
            _toggle(
              context: context,
              title: "Keep popups persistent",
              subtitle: "Prevent detached popups from closing on unfocus",
              value: user.keepPopupsOpen,
              onChanged: (bool v) async {
                user.keepPopupsOpen = v;
                await Boxes.updateSettings("keepPopupsOpen", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
            _toggle(
              context: context,
              title: "Drag popups by icon only",
              subtitle: "Drag QuickMenu popup by header icon rather than the full header",
              value: user.dragPopupsByIconOnly,
              onChanged: (bool v) async {
                user.dragPopupsByIconOnly = v;
                await Boxes.updateSettings("dragPopupsByIconOnly", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
            _toggle(
              context: context,
              title: "Quick Actions at the bottom",
              subtitle: "Place Quick Actions between pinned and tray",
              value: user.quickActionsAtBottom,
              onChanged: (bool v) async {
                user.quickActionsAtBottom = v;
                user.bottomBarOnTop = false;
                await Boxes.updateSettings("quickActionsAtBottom", v);
                await Boxes.updateSettings("bottomBarOnTop", false);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            if (user.quickActionsAtBottom)
              _toggle(
                context: context,
                title: "Bottom Bar at top",
                subtitle: "Move the bottom bar up to avoid crowding",
                value: user.bottomBarOnTop,
                onChanged: (bool v) async {
                  user.bottomBarOnTop = v;
                  await Boxes.updateSettings("bottomBarOnTop", v);
                  if (!mounted) return;
                  setState(() {});
                  QuickMenuFunctions.refreshQuickMenu();
                },
              ),
            _toggle(
              context: context,
              title: "Launcher Full Width Popups",
              subtitle: "Launcher popups span the full panel width",
              value: user.launcherFullPopups,
              onChanged: (bool v) async {
                user.launcherFullPopups = v;
                await Boxes.updateSettings("launcherFullPopups", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Taskbar Tab ───────────────────────────────────────────────────────────────

class _TaskbarTab extends StatefulWidget {
  const _TaskbarTab();

  @override
  State<_TaskbarTab> createState() => _TaskbarTabState();
}

class _TaskbarTabState extends State<_TaskbarTab> {
  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _toggle(
              context: context,
              title: "Taskbar Level Positioning",
              subtitle: "Align QuickMenu with the taskbar height",
              value: user.quickMenuAtTaskbarLevel,
              onChanged: (bool v) async {
                user.quickMenuAtTaskbarLevel = v;
                await Boxes.updateSettings("showQuickMenuAtTaskbarLevel", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
            _toggle(
              context: context,
              title: "Expanded Taskbar",
              subtitle: "High-density list with process labels",
              value: user.expandedTaskbar,
              onChanged: (bool v) async {
                user.expandedTaskbar = v;
                await Boxes.updateSettings("expandedTaskbar", v);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            _toggle(
              context: context,
              title: "Hover Slide Indicator",
              subtitle: "Slide item left and show accent bar on hover; off = color highlight only",
              value: user.taskbarHoverSlide,
              onChanged: (bool v) async {
                user.taskbarHoverSlide = v;
                await Boxes.updateSettings("taskbarHoverSlide", v);
                if (!mounted) return;
                setState(() {});
              },
            ),
            _toggle(
              context: context,
              title: "Quick Actions at the bottom",
              subtitle: "Place Quick Actions between pinned and tray",
              value: user.quickActionsAtBottom,
              onChanged: (bool v) async {
                user.quickActionsAtBottom = v;
                user.bottomBarOnTop = false;
                await Boxes.updateSettings("quickActionsAtBottom", v);
                await Boxes.updateSettings("bottomBarOnTop", false);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            if (user.quickActionsAtBottom)
              _toggle(
                context: context,
                title: "Bottom Bar at top",
                subtitle: "Move the bottom bar up to avoid crowding",
                value: user.bottomBarOnTop,
                onChanged: (bool v) async {
                  user.bottomBarOnTop = v;
                  await Boxes.updateSettings("bottomBarOnTop", v);
                  if (!mounted) return;
                  setState(() {});
                  QuickMenuFunctions.refreshQuickMenu();
                },
              ),
            _toggle(
              context: context,
              title: "Show Media Sessions",
              subtitle: "Display the current media session (music, browser, etc.)",
              value: user.mediaSessionsInTaskbar,
              onChanged: (bool v) async {
                user.mediaSessionsInTaskbar = v;
                await Boxes.updateSettings("showMediaSessionsInTaskbar", v);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            _sectionLabel(context, "DISPLAY PREFERENCE"),
            const SizedBox(height: 4),
            ...TaskBarAppsStyle.values.map((TaskBarAppsStyle style) => _buildStyleTile(context, style)),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleTile(BuildContext context, TaskBarAppsStyle style) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final bool isSelected = user.taskBarAppsStyle == style;

    final (String title, String subtitle, IconData icon) info = switch (style) {
      TaskBarAppsStyle.onlyActiveMonitor => (
          "Dynamic Isolation",
          "Show icons only on the active monitor",
          Icons.monitor_rounded
        ),
      TaskBarAppsStyle.activeMonitorFirst => (
          "Smart Sequence",
          "Prioritize active monitor in global sequence",
          Icons.reorder_rounded
        ),
      TaskBarAppsStyle.orderByActivity => (
          "Activity Stream",
          "Order by most frequently used across monitors",
          Icons.history_rounded
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primary.withValues(alpha: 0.2) : theme.dividerColor.withValues(alpha: 0.05),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isSelected
            ? null
            : () async {
                user.taskBarAppsStyle = style;
                await Boxes.updateSettings("taskBarAppsStyle", style.index);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected ? primary.withValues(alpha: 0.12) : theme.hintColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(info.$3, size: 16, color: isSelected ? primary : theme.hintColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      info.$1,
                      style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                    ),
                    Text(
                      info.$2,
                      style:
                          TextStyle(fontSize: Design.baseFontSize + 1, color: theme.hintColor.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 18, color: primary)
              else
                Icon(Icons.circle_outlined, size: 18, color: theme.hintColor.withValues(alpha: 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom Bar Tab ────────────────────────────────────────────────────────────

class _BottomBarTab extends StatefulWidget {
  const _BottomBarTab();

  @override
  State<_BottomBarTab> createState() => _BottomBarTabState();
}

class _BottomBarTabState extends State<_BottomBarTab> {
  List<String> _pinnedApps = <String>[];
  final Map<String, ExtractedIcon> _pinnedIcons = <String, ExtractedIcon>{};
  late Future<void> _iconsLoader;

  @override
  void initState() {
    super.initState();
    _pinnedApps = List<String>.from(Boxes.pinnedApps);
    _iconsLoader = _loadIcons();
  }

  Future<void> _loadIcons() async {
    _pinnedIcons.clear();
    for (final String path in _pinnedApps) {
      final ExtractedIcon icon = WinUtils.extractIcon(path);
      if (icon != null) _pinnedIcons[path] = icon;
    }
  }

  Future<void> _addApp() async {
    QuickMenuFunctions.keepOpen = true;
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'All Files': '*.*',
        'Executable (*.exe;*.ps1;*.sh;*.bat)': '*.exe;*.ps1;*.sh;*.bat',
      }
      ..defaultFilterIndex = 0
      ..defaultExtension = 'exe'
      ..title = 'Select any file';
    Future<void>.delayed(const Duration(milliseconds: 800), () => QuickMenuFunctions.keepOpen = false);
    final File? result = picker.getFile();
    if (result == null || Win32.getExe(result.path).contains(".dll")) return;
    if (_pinnedApps.contains(result.path)) return;
    _pinnedApps.add(result.path);
    final ExtractedIcon icon = WinUtils.extractIcon(result.path);
    if (icon != null) _pinnedIcons[result.path] = icon;
    await Boxes.updateSettings("pinnedApps", _pinnedApps);
    if (!mounted) return;
    setState(() {});
    QuickMenuFunctions.refreshQuickMenu();
  }

  Future<void> _removeApp(int index) async {
    final String removed = _pinnedApps.removeAt(index);
    _pinnedIcons.remove(removed);
    await Boxes.updateSettings("pinnedApps", _pinnedApps);
    if (!mounted) return;
    setState(() {});
    QuickMenuFunctions.refreshQuickMenu();
  }

  void _reorderApps(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final String item = _pinnedApps.removeAt(oldIndex);
    _pinnedApps.insert(newIndex, item);
    setState(() {});
    Boxes.updateSettings("pinnedApps", _pinnedApps);
    QuickMenuFunctions.refreshQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── System display toggles
            _toggle(
              context: context,
              title: "Show System Usage",
              subtitle: "Display RAM and CPU usage in the QuickMenu",
              value: user.showSystemUsage,
              onChanged: (bool v) async {
                user.showSystemUsage = v;
                await Boxes.updateSettings("showSystemUsage", v);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            _toggle(
              context: context,
              title: "LibreHardwareMonitor Data",
              subtitle: "Show CPU/GPU/RAM usage and temps. Configure it from Settings!",
              value: user.libreStats,
              onChanged: (bool v) async {
                user.libreStats = v;
                await Boxes.updateSettings("libreStats", v);
                if (v) {
                  user.taskManagerStats = false;
                  user.autoOpenTaskManager = false;
                  await Boxes.updateSettings("taskManagerStats", false);
                  await Boxes.updateSettings("autoOpenTaskManager", false);
                }
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            _toggle(
              context: context,
              title: "TaskManager System Usage",
              subtitle: "Show CPU/RAM from Task Manager when it is open",
              value: user.taskManagerStats,
              onChanged: (bool v) async {
                user.taskManagerStats = v;
                await Boxes.updateSettings("taskManagerStats", v);
                if (!v) {
                  user.autoOpenTaskManager = false;
                  await Boxes.updateSettings("autoOpenTaskManager", false);
                } else {
                  user.libreStats = false;
                  await Boxes.updateSettings("libreStats", false);
                }
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            if (user.taskManagerStats)
              _toggle(
                context: context,
                title: "Auto-start Task Manager",
                subtitle: "Open Task Manager on startup for persistent stats",
                value: user.autoOpenTaskManager,
                onChanged: (bool v) async {
                  user.autoOpenTaskManager = v;
                  await Boxes.updateSettings("autoOpenTaskManager", v);
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            _toggle(
              context: context,
              title: "Tray Bar",
              subtitle: "Show system tray icons in the bottom bar",
              value: user.showTrayBar,
              onChanged: (bool v) async {
                user.showTrayBar = v;
                await Boxes.updateSettings("showTrayBar", v);
                if (!mounted) return;
                setState(() {});
                QuickMenuFunctions.refreshQuickMenu();
              },
            ),
            if (user.showTrayBar) ...<Widget>[
              const SizedBox(height: 4),
              _buildTrayList(context),
            ],
            // ── Pinned apps
            const SizedBox(height: 8),
            _buildPinnedAppsHeader(context),
            const SizedBox(height: 4),
            _buildPinnedAppsList(context),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTrayList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Row(
            children: <Widget>[
              Text(
                "MANAGED TRAY ICONS",
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: primary.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                tooltip: "Reload tray list",
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  user.showTrayBar = false;
                  setState(() {});
                  user.showTrayBar = true;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        FutureBuilder<bool>(
          future: TrayWatcher.fetchTray(sort: false),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final List<TrayBarInfo> items =
                TrayWatcher.trayList.where((TrayBarInfo e) => e.processExe != "explorer.exe").toList();
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  "No tray icons found",
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: theme.hintColor),
                ),
              );
            }
            return Column(
              children: items.map((TrayBarInfo item) => _buildTrayItem(context, item)).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTrayItem(BuildContext context, TrayBarInfo item) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 2),
          Image.memory(
            item.iconData,
            width: 20,
            height: 20,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const Icon(Icons.check_box_outline_blank, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.processExe.isEmpty ? "Permission denied" : item.processExe,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontStyle: item.processExe.isEmpty ? FontStyle.italic : FontStyle.normal,
                color: item.processExe.isEmpty ? theme.hintColor : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ToggleButtons(
            constraints: const BoxConstraints(minHeight: 26, minWidth: 26),
            borderRadius: BorderRadius.circular(6),
            isSelected: <bool>[item.isPinned, !item.isVisible],
            onPressed: (int index) async {
              final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
              final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
              if (index == 0) {
                if (pinned.contains(item.processExe)) {
                  pinned.remove(item.processExe);
                } else {
                  pinned.add(item.processExe);
                  hidden.remove(item.processExe);
                }
              } else {
                if (hidden.contains(item.processExe)) {
                  hidden.remove(item.processExe);
                } else {
                  hidden.add(item.processExe);
                  pinned.remove(item.processExe);
                }
              }
              await Boxes.updateSettings("pinnedTray", pinned);
              await Boxes.updateSettings("hiddenTray", hidden);
              if (!mounted) return;
              setState(() {});
            },
            children: const <Widget>[
              CustomTooltip(message: "Pin to bar", child: Icon(Icons.push_pin_rounded, size: 13)),
              CustomTooltip(message: "Hide icon", child: Icon(Icons.visibility_off_rounded, size: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAppsHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(Icons.push_pin_outlined, size: 16, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(
          "PINNED FILES",
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: theme.colorScheme.primary),
          tooltip: "Add pinned file",
          visualDensity: VisualDensity.compact,
          onPressed: _addApp,
        ),
      ],
    );
  }

  Widget _buildPinnedAppsList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_pinnedApps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            "No pinned files. Tap + to add one.",
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: theme.hintColor.withValues(alpha: 0.5)),
          ),
        ),
      );
    }
    return FutureBuilder<void>(
      future: _iconsLoader,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        return ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          dragStartBehavior: DragStartBehavior.down,
          itemCount: _pinnedApps.length,
          onReorderItem: _reorderApps,
          itemBuilder: (BuildContext context, int index) {
            final String path = _pinnedApps[index];
            final ExtractedIcon? icon = _pinnedIcons[path];
            return Container(
              key: ValueKey<String>(path),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: <Widget>[
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.drag_indicator_rounded,
                          size: 18, color: theme.colorScheme.onSurface.withAlpha(60)),
                    ),
                  ),
                  if (icon != null)
                    buildExtractedIcon(
                      icon,
                      width: 20,
                      errorBuilder: (_, __, ___) => const Icon(Icons.check_box_outline_blank, size: 18),
                      fallback: const Icon(Icons.check_box_outline_blank, size: 18),
                    )
                  else
                    const Icon(Icons.check_box_outline_blank, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Win32.getExe(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                    tooltip: "Remove",
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeApp(index),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Quick Actions Tab ─────────────────────────────────────────────────────────

class _QuickActionsTab extends StatefulWidget {
  const _QuickActionsTab();

  @override
  State<_QuickActionsTab> createState() => _QuickActionsTabState();
}

class _QuickActionsTabState extends State<_QuickActionsTab> {
  final List<String> _active = <String>[];
  final List<String> _disabled = <String>[];
  final Map<String, IconData> _icons = <String, IconData>{};

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contentKey = GlobalKey();
  EdgeDraggingAutoScroller? _autoScroller;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _icons.addAll(
      quickActionsMap.map((String k, QuickAction v) => MapEntry<String, IconData>(k, v.icon)),
    );
    final List<String> saved = Boxes().topBarWidgets;
    bool foundDeactivated = false;
    for (final String item in saved) {
      if (item == "Deactivated:") {
        foundDeactivated = true;
        continue;
      }
      if (!_icons.containsKey(item)) continue;
      if (foundDeactivated) {
        _disabled.add(item);
      } else {
        _active.add(item);
      }
    }
    _saveOnly();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onReorderStart(int _) {
    _dragging = true;
    final BuildContext? ctx = _contentKey.currentContext;
    if (ctx == null) return;
    final ScrollableState scrollable = Scrollable.of(ctx);
    if (_autoScroller?.scrollable != scrollable) {
      _autoScroller = EdgeDraggingAutoScroller(scrollable, velocityScalar: 50);
    }
  }

  void _onReorderEnd(int _) {
    _dragging = false;
    _autoScroller?.stopAutoScroll();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragging) return;
    _autoScroller?.startAutoScrollIfNecessary(Rect.fromCenter(center: event.position, width: 1, height: 1));
  }

  void _saveOnly() {
    Boxes.updateSettings("topBarWidgets", <String>[..._active, "Deactivated:", ..._disabled]);
  }

  void _persist() {
    _saveOnly();
    QuickMenuFunctions.refreshQuickMenu();
  }

  void _disable(String item) {
    setState(() {
      _active.remove(item);
      _disabled.insert(0, item);
    });
    _persist();
  }

  void _enable(String item) {
    setState(() {
      _disabled.remove(item);
      _active.add(item);
    });
    _persist();
  }

  void _reorderActive(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final String item = _active.removeAt(oldIndex);
    _active.insert(newIndex, item);
    setState(() {});
    _persist();
  }

  void _reorderDisabled(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final String item = _disabled.removeAt(oldIndex);
    _disabled.insert(newIndex, item);
    setState(() {});
    _persist();
  }

  String _label(String item) {
    return item
        .replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match m) => ' ${m[0]}')
        .replaceAll("Button", "")
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      controller: _scrollController,
      child: Listener(
        onPointerMove: _onPointerMove,
        child: Padding(
          key: _contentKey,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildSectionHeader(context, "ENABLED", Icons.check_circle_outline_rounded, active: true),
              const SizedBox(height: 4),
              ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                itemCount: _active.length,
                onReorderItem: _reorderActive,
                onReorderStart: _onReorderStart,
                onReorderEnd: _onReorderEnd,
                itemBuilder: (BuildContext context, int index) {
                  final String item = _active[index];
                  return _buildRow(
                    key: ValueKey<String>(item),
                    context: context,
                    index: index,
                    item: item,
                    active: true,
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildSectionHeader(context, "DISABLED", Icons.block_rounded, active: false),
              const SizedBox(height: 4),
              ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                itemCount: _disabled.length,
                onReorderItem: _reorderDisabled,
                onReorderStart: _onReorderStart,
                onReorderEnd: _onReorderEnd,
                itemBuilder: (BuildContext context, int index) {
                  final String item = _disabled[index];
                  return _buildRow(
                    key: ValueKey<String>(item),
                    context: context,
                    index: index,
                    item: item,
                    active: false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label, IconData icon, {required bool active}) {
    final ThemeData theme = Theme.of(context);
    final Color color = active ? theme.colorScheme.primary : theme.hintColor;
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: color.withValues(alpha: active ? 0.7 : 0.4)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: color.withValues(alpha: active ? 0.7 : 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildRow({
    required Key key,
    required BuildContext context,
    required int index,
    required String item,
    required bool active,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: active ? primary.withValues(alpha: 0.04) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: active ? primary.withValues(alpha: 0.12) : onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 18,
                color: onSurface.withValues(alpha: active ? 0.35 : 0.2),
              ),
            ),
          ),
          Icon(
            _icons[item] ?? Icons.circle_outlined,
            size: 15,
            color: active ? primary.withValues(alpha: 0.8) : onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _label(item),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? onSurface : onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              active ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 17,
            ),
            color: active ? theme.colorScheme.error.withValues(alpha: 0.6) : primary.withValues(alpha: 0.6),
            tooltip: active ? "Disable" : "Enable",
            visualDensity: VisualDensity.compact,
            onPressed: active ? () => _disable(item) : () => _enable(item),
          ),
        ],
      ),
    );
  }
}
