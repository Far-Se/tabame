import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/window_watcher.dart';

class QuickmenuTaskbar extends StatefulWidget {
  const QuickmenuTaskbar({super.key});

  @override
  State<QuickmenuTaskbar> createState() => _QuickmenuTaskbarState();
}

class _QuickmenuTaskbarState extends State<QuickmenuTaskbar> {
  List<MapEntry<String, String>> taskbarRewrites = Boxes().taskBarRewrites.entries.toList();
  final List<TextEditingController> reWriteSearchController = <TextEditingController>[];
  final List<TextEditingController> reWriteReplaceController = <TextEditingController>[];

  List<MapEntry<String, String>> appIconRewrites = Boxes().iconsRewrite.entries.toList();
  final List<TextEditingController> appIconSearchController = <TextEditingController>[];
  final List<TextEditingController> appIconPathController = <TextEditingController>[];
  @override
  void initState() {
    super.initState();
    taskbarRewrites = Boxes().taskBarRewrites.entries.toList();
    for (MapEntry<String, String> item in taskbarRewrites) {
      reWriteSearchController.add(TextEditingController(text: item.key));
      reWriteReplaceController.add(TextEditingController(text: item.value));
    }

    appIconRewrites = Boxes().iconsRewrite.entries.toList();
    for (MapEntry<String, String> item in appIconRewrites) {
      appIconSearchController.add(TextEditingController(text: item.key));
      appIconPathController.add(TextEditingController(text: item.value));
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme.copyWith(
              dense: true,
              style: ListTileStyle.drawer,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              minVerticalPadding: 0,
              visualDensity: VisualDensity.compact,
              horizontalTitleGap: 0,
            ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTaskbarSettingsCard(),
              const SizedBox(height: 20),
              _buildTaskbarRewritesCard(),
              const SizedBox(height: 20),
              _buildAppIconRewritesCard(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskbarSettingsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            const ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading: Icon(Icons.view_list_outlined),
              title: Text("Taskbar Settings", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Configure taskbar visibility and app ordering"),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Show QuickMenu at Taskbar Level"),
              subtitle: const Text("Display the quick menu controls directly from the taskbar"),
              secondary: const Icon(Icons.dock_outlined, size: 20),
              value: globalSettings.showQuickMenuAtTaskbarLevel,
              onChanged: (bool newValue) async {
                globalSettings.showQuickMenuAtTaskbarLevel = newValue;
                await Boxes.updateSettings("showQuickMenuAtTaskbarLevel", globalSettings.showQuickMenuAtTaskbarLevel);
                if (!mounted) return;
                setState(() {});
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RadioGroup<TaskBarAppsStyle>(
                  onChanged: (TaskBarAppsStyle? value) async {
                    globalSettings.taskBarAppsStyle = value ?? TaskBarAppsStyle.activeMonitorFirst;
                    await Boxes.updateSettings("taskBarAppsStyle", globalSettings.taskBarAppsStyle.index);
                    if (!mounted) return;
                    setState(() {});
                  },
                  groupValue: globalSettings.taskBarAppsStyle,
                  child: RadioTheme(
                    data: Theme.of(context).radioTheme.copyWith(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 20,
                        ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Text("Taskbar Order", style: Theme.of(context).textTheme.labelLarge),
                        ),
                        const RadioListTile<TaskBarAppsStyle>(
                          title: Text('Active Monitor First'),
                          subtitle: Text("Prioritize windows on the active monitor"),
                          value: TaskBarAppsStyle.activeMonitorFirst,
                        ),
                        const RadioListTile<TaskBarAppsStyle>(
                          title: Text('Only Active Monitor'),
                          subtitle: Text("Show taskbar apps from the active monitor only"),
                          value: TaskBarAppsStyle.onlyActiveMonitor,
                        ),
                        const RadioListTile<TaskBarAppsStyle>(
                          title: Text('Order by Activity'),
                          subtitle: Text("Keep the most recently active apps first"),
                          value: TaskBarAppsStyle.orderByActivity,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskbarRewritesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading: const Icon(Icons.find_replace_outlined),
              title: const Text("Taskbar Rewrites", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Create regex-aware label replacements for taskbar items"),
              trailing: IconButton(
                onPressed: () {
                  taskbarRewrites.insert(0, const MapEntry<String, String>("find", "replace"));
                  reWriteSearchController.insert(0, TextEditingController(text: "find"));
                  reWriteReplaceController.insert(0, TextEditingController(text: "replace"));
                  setState(() {});
                },
                icon: const Icon(Icons.add_circle_outline),
                tooltip: "Add rewrite",
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: <Widget>[
                  Text("Regex Tool", style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Search expressions are applied to taskbar labels and replaced inline.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),
            if (taskbarRewrites.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "No rewrites yet. Add a search and replacement rule to clean up taskbar titles.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: taskbarRewrites.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) => _buildRewriteItem(index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewriteItem(int index) {
    final Color borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildRewriteField(
              controller: reWriteSearchController[index],
              labelText: "Find",
              onSaved: () => saveTaskBarRewrite(index),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Theme.of(context).hintColor,
            ),
          ),
          Expanded(
            child: _buildRewriteField(
              controller: reWriteReplaceController[index],
              labelText: "Replace",
              onSaved: () => saveTaskBarRewrite(index),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            tooltip: "Delete Rewrite",
            onPressed: () async {
              taskbarRewrites.removeAt(index);
              reWriteSearchController.removeAt(index);
              reWriteReplaceController.removeAt(index);
              await _persistTaskbarRewrites();
              if (!mounted) return;
              setState(() {});
            },
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
    return Focus(
      onFocusChange: (bool hasFocus) async {
        if (!hasFocus) {
          final bool saved = await onSaved();
          if (!saved && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Error: Regex failed or search is empty."),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red.shade200,
            ));
          }
          if (mounted) setState(() {});
        }
      },
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: labelText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }

  Future<bool> saveTaskBarRewrite(int index) async {
    if (reWriteSearchController[index].text.isEmpty) return false;
    try {
      RegExp(reWriteSearchController[index].text, caseSensitive: false).hasMatch("ciulama");
    } catch (_) {
      return false;
    }
    if (reWriteReplaceController[index].text.isNotEmpty) {
      taskbarRewrites[index] =
          MapEntry<String, String>(reWriteSearchController[index].text, reWriteReplaceController[index].text);
    } else {
      taskbarRewrites[index] = MapEntry<String, String>(reWriteSearchController[index].text, " ");
    }
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

  Widget _buildAppIconRewritesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading: const Icon(Icons.image_outlined),
              title: const Text("App Icon Rewrites", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Replace application icons based on executable path"),
              trailing: IconButton(
                onPressed: () {
                  appIconRewrites.insert(0, const MapEntry<String, String>("exe name or path", ""));
                  appIconSearchController.insert(0, TextEditingController(text: "exe name or path"));
                  appIconPathController.insert(0, TextEditingController(text: ""));
                  setState(() {});
                },
                icon: const Icon(Icons.add_circle_outline),
                tooltip: "Add rewrite",
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: <Widget>[
                  Text("Match & Pick", style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Enter part of the exe path (e.g. 'Code.exe') and pick a new image.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),
            if (appIconRewrites.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "No rewrites yet. Add a rule to change app icons.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: appIconRewrites.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) => _buildAppIconRewriteItem(index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIconRewriteItem(int index) {
    final Color borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.18);
    final String iconPath = appIconPathController[index].text;
    final bool hasValidIcon = iconPath.isNotEmpty && File(iconPath).existsSync();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: _buildRewriteField(
              controller: appIconSearchController[index],
              labelText: "Match Path",
              onSaved: () => saveAppIconRewrite(index),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Theme.of(context).hintColor,
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
            ),
            child: hasValidIcon
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.file(File(iconPath), fit: BoxFit.contain, filterQuality: FilterQuality.high),
                  )
                : const Icon(Icons.image_not_supported_outlined, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _buildRewriteField(
              controller: appIconPathController[index],
              labelText: "Icon Path",
              onSaved: () => saveAppIconRewrite(index),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, size: 20),
            tooltip: "Pick Image",
            onPressed: () async {
              final OpenFilePicker file = OpenFilePicker()
                ..filterSpecification = <String, String>{
                  'Image files (*.png; *.jpg; *.jpeg; *.ico)': '*.png;*.jpg;*.jpeg;*.ico'
                }
                ..defaultFilterIndex = 0
                ..title = 'Select an icon image';
              final File? result = file.getFile();
              if (result != null) {
                appIconPathController[index].text = result.path;
                await saveAppIconRewrite(index);
                setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            tooltip: "Delete Rewrite",
            onPressed: () async {
              appIconRewrites.removeAt(index);
              appIconSearchController.removeAt(index);
              appIconPathController.removeAt(index);
              await _persistAppIconRewrites();
              if (!mounted) return;
              setState(() {});
            },
          ),
        ],
      ),
    );
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
}
