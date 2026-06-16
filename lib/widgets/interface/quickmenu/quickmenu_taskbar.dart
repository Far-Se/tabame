import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/app_opacity.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/window_watcher.dart';
import '../../widgets/mini_switch.dart';

class QMTaskbar extends StatefulWidget {
  const QMTaskbar({super.key});

  @override
  State<QMTaskbar> createState() => _QMTaskbarState();
}

class _QMTaskbarState extends State<QMTaskbar> {
  List<MapEntry<String, String>> taskbarRewrites = Boxes.taskBarRewrites.entries.toList();
  final List<TextEditingController> reWriteSearchController = <TextEditingController>[];
  final List<TextEditingController> reWriteReplaceController = <TextEditingController>[];

  List<MapEntry<String, String>> appIconRewrites = Boxes.iconsRewrite.entries.toList();
  final List<TextEditingController> appIconSearchController = <TextEditingController>[];
  final List<TextEditingController> appIconPathController = <TextEditingController>[];

  List<MapEntry<String, List<String>>> taskbarBadges = Boxes.taskbarBadges.entries.toList();
  final List<TextEditingController> badgeExeController = <TextEditingController>[];
  final List<TextEditingController> badgeTitleController = <TextEditingController>[];
  final List<TextEditingController> badgeHideRegexController = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  void _syncControllers() {
    for (TextEditingController c in reWriteSearchController) {
      c.dispose();
    }
    for (TextEditingController c in reWriteReplaceController) {
      c.dispose();
    }
    for (TextEditingController c in appIconSearchController) {
      c.dispose();
    }
    for (TextEditingController c in appIconPathController) {
      c.dispose();
    }
    reWriteSearchController.clear();
    reWriteReplaceController.clear();
    appIconSearchController.clear();
    appIconPathController.clear();

    taskbarRewrites = Boxes.taskBarRewrites.entries.toList();
    for (MapEntry<String, String> item in taskbarRewrites) {
      reWriteSearchController.add(TextEditingController(text: item.key));
      reWriteReplaceController.add(TextEditingController(text: item.value));
    }

    appIconRewrites = Boxes.iconsRewrite.entries.toList();
    for (MapEntry<String, String> item in appIconRewrites) {
      appIconSearchController.add(TextEditingController(text: item.key));
      appIconPathController.add(TextEditingController(text: item.value));
    }

    for (TextEditingController c in badgeExeController) {
      c.dispose();
    }
    for (TextEditingController c in badgeTitleController) {
      c.dispose();
    }
    for (TextEditingController c in badgeHideRegexController) {
      c.dispose();
    }
    badgeExeController.clear();
    badgeTitleController.clear();
    badgeHideRegexController.clear();

    taskbarBadges = Boxes.taskbarBadges.entries.toList();
    for (MapEntry<String, List<String>> item in taskbarBadges) {
      badgeExeController.add(TextEditingController(text: item.key));
      badgeTitleController.add(TextEditingController(text: item.value[0]));
      badgeHideRegexController.add(TextEditingController(text: item.value.length > 1 ? item.value[1] : ""));
    }
  }

  @override
  void dispose() {
    for (TextEditingController item in reWriteSearchController) {
      item.dispose();
    }
    for (TextEditingController item in reWriteReplaceController) {
      item.dispose();
    }
    for (TextEditingController item in appIconSearchController) {
      item.dispose();
    }
    for (TextEditingController item in appIconPathController) {
      item.dispose();
    }
    for (TextEditingController item in badgeExeController) {
      item.dispose();
    }
    for (TextEditingController item in badgeTitleController) {
      item.dispose();
    }
    for (TextEditingController item in badgeHideRegexController) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildTaskbarSettingsCard(),
          const SizedBox(height: 20),
          _buildTaskbarRewritesCard(),
          const SizedBox(height: 20),
          _buildAppIconRewritesCard(),
          const SizedBox(height: 20),
          _buildBadgeMonitoringCard(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildTaskbarSettingsCard() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildPanelHeader(
            icon: Icons.compress_rounded,
            title: "TASKBAR ENGINE",
            subtitle: "Global taskbar behavior and display logic",
          ),
          const Divider(height: 1),
          _buildToggleTile(
            title: "Taskbar Level Positioning",
            subtitle: "Maintain QuickMenu alignment with taskbar height",
            value: user.quickMenuAtTaskbarLevel,
            onChanged: (bool v) async {
              user.quickMenuAtTaskbarLevel = v;
              await Boxes.updateSettings("showQuickMenuAtTaskbarLevel", user.quickMenuAtTaskbarLevel);
              if (!mounted) return;
              setState(() {});
            },
          ),
          const Divider(height: 1),
          _buildToggleTile(
            title: "Expanded Taskbar",
            subtitle: "High-density technical list with process labels",
            value: user.expandedTaskbar,
            onChanged: (bool v) async {
              user.expandedTaskbar = v;
              await Boxes.updateSettings("expandedTaskbar", user.expandedTaskbar);
              if (!mounted) return;
              setState(() {});
            },
          ),
          const Divider(height: 1),
          _buildToggleTile(
            title: "Quick Actions at the bottom",
            subtitle: "Put Quick Action on the bottom, between pinned and tray",
            value: user.quickActionsAtBottom,
            onChanged: (bool v) async {
              user.quickActionsAtBottom = v;
              user.bottomBarOnTop = false;
              await Boxes.updateSettings("quickActionsAtBottom", user.quickActionsAtBottom);
              await Boxes.updateSettings("bottomBarOnTop", user.bottomBarOnTop);
              if (!mounted) return;
              setState(() {});
            },
          ),
          if (user.quickActionsAtBottom) ...<Widget>[
            const Divider(height: 1),
            _buildToggleTile(
              title: "Bottom Bar at top",
              subtitle: "Put Buttom bar at the top to not get crowded",
              value: user.bottomBarOnTop,
              onChanged: (bool v) async {
                user.bottomBarOnTop = v;
                await Boxes.updateSettings("bottomBarOnTop", user.bottomBarOnTop);
                if (!mounted) return;
                setState(() {});
              },
            ),
          ],
          const Divider(height: 1),
          _buildToggleTile(
            title: "Show Media Sessions",
            subtitle: "It will show curent Media Session like Music Player or Youtube/Browser",
            value: user.mediaSessionsInTaskbar,
            onChanged: (bool v) async {
              user.mediaSessionsInTaskbar = v;
              await Boxes.updateSettings("showMediaSessionsInTaskbar", user.mediaSessionsInTaskbar);
              if (!mounted) return;
              setState(() {});
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "DISPLAY PREFERENCE",
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: scheme.primary.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                _buildStyleSelector(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleSelector() {
    return Column(
      children: TaskBarAppsStyle.values.map((TaskBarAppsStyle style) => _buildStyleTile(style)).toList(),
    );
  }

  Widget _buildStyleTile(TaskBarAppsStyle style) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isSelected = user.taskBarAppsStyle == style;

    String title = "";
    String subtitle = "";
    IconData icon = Icons.circle_outlined;

    switch (style) {
      case TaskBarAppsStyle.onlyActiveMonitor:
        title = "Dynamic Isolation";
        subtitle = "Show icons only on the active monitor";
        icon = Icons.monitor_rounded;
        break;
      case TaskBarAppsStyle.activeMonitorFirst:
        title = "Smart Sequence";
        subtitle = "Prioritize active monitor in global sequence";
        icon = Icons.reorder_rounded;
        break;
      case TaskBarAppsStyle.orderByActivity:
        title = "Activity Stream";
        subtitle = "Order by most frequently used across monitors";
        icon = Icons.history_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? scheme.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? scheme.primary.withValues(alpha: 0.2) : theme.dividerColor.withValues(alpha: 0.05),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          user.taskBarAppsStyle = style;
          await Boxes.updateSettings("taskBarAppsStyle", user.taskBarAppsStyle.index);
          if (!mounted) return;
          setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary.withValues(alpha: 0.12) : theme.hintColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? scheme.primary : theme.hintColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
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
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary)
              else
                Icon(Icons.circle_outlined, size: 20, color: theme.hintColor.withValues(alpha: 0.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskbarRewritesCard() {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        children: <Widget>[
          _buildPanelHeader(
            icon: Icons.find_replace_outlined,
            title: "LABEL REWRITES",
            subtitle: "Regex-based title transformation engine",
            trailing: FilledButton.tonalIcon(
              onPressed: () {
                taskbarRewrites.insert(0, const MapEntry<String, String>("", ""));
                reWriteSearchController.insert(0, TextEditingController());
                reWriteReplaceController.insert(0, TextEditingController());
                setState(() {});
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text("Add Rule"),
            ),
          ),
          const Divider(height: 1),
          if (taskbarRewrites.isEmpty)
            _buildEmptyState(
              icon: Icons.auto_fix_off_rounded,
              message: "No active label rewrites provisioned.",
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: taskbarRewrites.length,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) => _buildRewriteItem(index),
            ),
        ],
      ),
    );
  }

  Widget _buildRewriteItem(int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildRewriteField(
                  controller: reWriteSearchController[index],
                  labelText: "Pattern (Regex)",
                  onSaved: () => saveTaskBarRewrite(index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded, size: 16, color: theme.hintColor.withValues(alpha: 0.3)),
              ),
              Expanded(
                child: _buildRewriteField(
                  controller: reWriteReplaceController[index],
                  labelText: "Replacement",
                  onSaved: () => saveTaskBarRewrite(index),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.7)),
                onPressed: () async {
                  taskbarRewrites.removeAt(index);
                  reWriteSearchController.removeAt(index).dispose();
                  reWriteReplaceController.removeAt(index).dispose();
                  await _persistTaskbarRewrites();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppIconRewritesCard() {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        children: <Widget>[
          _buildPanelHeader(
            icon: Icons.image_search_rounded,
            title: "ICONS OVERRIDES",
            subtitle: "Custom path mappings for application icons",
            trailing: FilledButton.tonalIcon(
              onPressed: () {
                appIconRewrites.insert(0, const MapEntry<String, String>("", ""));
                appIconSearchController.insert(0, TextEditingController());
                appIconPathController.insert(0, TextEditingController());
                setState(() {});
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text("Add Rule"),
            ),
          ),
          const Divider(height: 1),
          if (appIconRewrites.isEmpty)
            _buildEmptyState(
              icon: Icons.image_not_supported_rounded,
              message: "No custom asset overrides provisioned.",
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: appIconRewrites.length,
              separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) => _buildAppIconRewriteItem(index),
            ),
        ],
      ),
    );
  }

  Widget _buildAppIconRewriteItem(int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String iconPath = appIconPathController[index].text;
    final bool hasValidIcon = iconPath.isNotEmpty && File(iconPath).existsSync();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
            ),
            child: hasValidIcon
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.file(File(iconPath), fit: BoxFit.contain),
                    ),
                  )
                : Icon(Icons.image_outlined, size: 20, color: theme.hintColor.withValues(alpha: 0.3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _buildRewriteField(
              controller: appIconSearchController[index],
              labelText: "Executable Path / Match",
              onSaved: () => saveAppIconRewrite(index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: _buildRewriteField(
              controller: appIconPathController[index],
              labelText: "Target Asset Path",
              onSaved: () => saveAppIconRewrite(index),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: <Widget>[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                onPressed: () => _pickIconForRewrite(index),
              ),
              const SizedBox(height: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.7)),
                onPressed: () async {
                  appIconRewrites.removeAt(index);
                  appIconSearchController.removeAt(index).dispose();
                  appIconPathController.removeAt(index).dispose();
                  await _persistAppIconRewrites();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: theme.hintColor.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: Design.baseFontSize + 1, color: theme.hintColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: MiniToggleSwitch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: theme.hintColor.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor.withValues(alpha: 0.5), fontSize: Design.baseFontSize + 2),
          ),
        ],
      ),
    );
  }

  Widget _buildRewriteField({
    required TextEditingController controller,
    required String labelText,
    required Future<bool> Function() onSaved,
  }) {
    final ThemeData theme = Theme.of(context);

    return Focus(
      onFocusChange: (bool hasFocus) async {
        if (!hasFocus) {
          await onSaved();
          if (mounted) setState(() {});
        }
      },
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: theme.hintColor),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }

  Future<void> _pickIconForRewrite(int index) async {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'Image files (*.png; *.jpg; *.jpeg; *.ico)': '*.png;*.jpg;*.jpeg;*.ico'}
      ..defaultFilterIndex = 0
      ..title = 'Select an icon image';
    final File? result = file.getFile();
    if (result != null) {
      appIconPathController[index].text = result.path;
      await saveAppIconRewrite(index);
      setState(() {});
    }
  }

  Future<bool> saveTaskBarRewrite(int index) async {
    if (reWriteSearchController[index].text.isEmpty) return false;
    try {
      RegExp(reWriteSearchController[index].text, caseSensitive: false).hasMatch("test");
    } catch (_) {
      return false;
    }
    taskbarRewrites[index] =
        MapEntry<String, String>(reWriteSearchController[index].text, reWriteReplaceController[index].text);
    await _persistTaskbarRewrites();
    return true;
  }

  Future<void> _persistTaskbarRewrites() async {
    final Map<String, String> reWrites = <String, String>{};
    for (int i = 0; i < taskbarRewrites.length; i++) {
      reWrites[taskbarRewrites.elementAt(i).key] = taskbarRewrites.elementAt(i).value;
    }
    await Boxes.updateSettings("taskBarRewrites", jsonEncode(reWrites));
    WindowWatcher.taskBarRewrites = reWrites;
  }

  Future<bool> saveAppIconRewrite(int index) async {
    if (appIconSearchController[index].text.isEmpty) return false;
    appIconRewrites[index] =
        MapEntry<String, String>(appIconSearchController[index].text, appIconPathController[index].text);
    await _persistAppIconRewrites();
    return true;
  }

  Future<void> _persistAppIconRewrites() async {
    final Map<String, String> reWrites = <String, String>{};
    for (int i = 0; i < appIconRewrites.length; i++) {
      reWrites[appIconRewrites.elementAt(i).key] = appIconRewrites.elementAt(i).value;
    }
    await Boxes.updateSettings("iconsRewrite", jsonEncode(reWrites));
  }

  Widget _buildBadgeMonitoringCard() {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        children: <Widget>[
          _buildPanelHeader(
            icon: Icons.notifications_active_outlined,
            title: "BADGE MONITORING",
            subtitle: "Map taskbar badges to specific application windows",
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () {
                    showQuickMenuModal(
                      context: context,
                      maxWidth: 500,
                      child: const _AllBadgesModal(),
                    );
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text("see all badges"),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    taskbarBadges.insert(0, const MapEntry<String, List<String>>("", <String>["", ""]));
                    badgeExeController.insert(0, TextEditingController());
                    badgeTitleController.insert(0, TextEditingController());
                    badgeHideRegexController.insert(0, TextEditingController());
                    setState(() {});
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text("Add Badge"),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (taskbarBadges.isEmpty)
            _buildEmptyState(
              icon: Icons.notifications_off_outlined,
              message: "No badge monitoring rules configured.",
            )
          else
            FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: taskbarBadges.length,
                separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) => _buildBadgeItem(index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildRewriteField(
                  controller: badgeExeController[index],
                  labelText: "Application Exe (e.g. discord.exe)",
                  onSaved: () => saveBadgeRule(index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.link_rounded, size: 16, color: theme.hintColor.withValues(alpha: 0.3)),
              ),
              Expanded(
                child: _buildRewriteField(
                  controller: badgeTitleController[index],
                  labelText: "UIA Name Partial Match",
                  onSaved: () => saveBadgeRule(index),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRewriteField(
                  controller: badgeHideRegexController[index],
                  labelText: "Hide if Badge Matches (Regex)",
                  onSaved: () => saveBadgeRule(index),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.7)),
                onPressed: () async {
                  taskbarBadges.removeAt(index);
                  badgeExeController.removeAt(index).dispose();
                  badgeTitleController.removeAt(index).dispose();
                  badgeHideRegexController.removeAt(index).dispose();
                  await _persistBadgeRules();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool> saveBadgeRule(int index) async {
    if (badgeExeController[index].text.isEmpty) return false;
    if (badgeHideRegexController[index].text.isNotEmpty) {
      try {
        RegExp(badgeHideRegexController[index].text, caseSensitive: false).hasMatch("test");
      } catch (_) {
        return false;
      }
    }
    taskbarBadges[index] = MapEntry<String, List<String>>(badgeExeController[index].text,
        <String>[badgeTitleController[index].text, badgeHideRegexController[index].text]);
    await _persistBadgeRules();
    return true;
  }

  Future<void> _persistBadgeRules() async {
    final Map<String, List<String>> rules = <String, List<String>>{};
    for (int i = 0; i < taskbarBadges.length; i++) {
      rules[taskbarBadges.elementAt(i).key] = taskbarBadges.elementAt(i).value;
    }
    await Boxes.updateSettings("taskbarBadges", jsonEncode(rules));
    Boxes.taskbarBadges = rules;
  }
}

class _AllBadgesModal extends StatefulWidget {
  const _AllBadgesModal();

  @override
  State<_AllBadgesModal> createState() => _AllBadgesModalState();
}

class _AllBadgesModalState extends State<_AllBadgesModal> {
  bool _loading = true;
  List<TaskbarButtonInfo> _badgeItems = <TaskbarButtonInfo>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });

    final List<TaskbarButtonInfo> taskbarItems = await TaskbarUia.getButtonInfos();

    if (mounted) {
      setState(() {
        _badgeItems = taskbarItems;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = Design.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.badge_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      "ALL OPENED APP BADGES",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Currently active UIA taskbar items and their badge/helpText status",
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _badgeItems.isEmpty
                  ? Center(
                      child: Text(
                        "No taskbar items found",
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _badgeItems.length,
                      separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final TaskbarButtonInfo button = _badgeItems[index];

                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.cardColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: <Widget>[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  button.uiaName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (button.helpText.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: accent.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    button.helpText,
                                    style: TextStyle(
                                      fontSize: Design.baseFontSize + 1,
                                      fontWeight: FontWeight.bold,
                                      color: accent,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  "-",
                                  style: TextStyle(
                                    fontSize: Design.baseFontSize + 2,
                                    color: theme.hintColor.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
