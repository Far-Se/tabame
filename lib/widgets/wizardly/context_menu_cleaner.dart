import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/win32/registry.dart';
import '../../models/win32/win_utils.dart';
import '../../models/wizardly/context_menu_item.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/text_input.dart';

class ContextMenuCleaner extends StatefulWidget {
  const ContextMenuCleaner({super.key});

  @override
  ContextMenuCleanerState createState() => ContextMenuCleanerState();
}

enum ContextTarget { allFiles, folder, directory, extension }

class ContextMenuCleanerState extends State<ContextMenuCleaner> {
  ContextTarget target = ContextTarget.allFiles;
  String extension = ".txt";
  List<ContextMenuItem> items = <ContextMenuItem>[];
  bool isLoading = false;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    isAdmin = WinUtils.isAdministrator();
  }

  Future<void> _scan() async {
    setState(() {
      isLoading = true;
      items.clear();
    });

    final List<String> paths = <String>[];
    if (target == ContextTarget.allFiles) {
      paths.add("*");
      paths.add("AllFilesystemObjects");
    } else if (target == ContextTarget.folder) {
      paths.add("Folder");
      paths.add("Directory");
      paths.add("AllFilesystemObjects");
    } else if (target == ContextTarget.directory) {
      paths.add(r"Directory\Background");
    } else {
      String ext = extension.trim();
      if (ext.isNotEmpty && !ext.startsWith(".")) {
        ext = ".$ext";
      }
      if (ext.isNotEmpty) {
        paths.add(ext);
        paths.add("SystemFileAssociations\\$ext");
        // Follow Progid
        final RegistryKey? extKey = _openRegistryPath(ext);
        if (extKey != null) {
          final String? progid = extKey.getValueAsString("");
          if (progid != null && progid.isNotEmpty) {
            paths.add(progid);
          }
          final String? perceivedType = extKey.getValueAsString("PerceivedType");
          if (perceivedType != null && perceivedType.isNotEmpty) {
            paths.add("SystemFileAssociations\\$perceivedType");
          }
          extKey.close();
        }
        // Global handlers also apply
        paths.add("*");
        paths.add("AllFilesystemObjects");
      }
    }

    for (final String path in paths) {
      // Scan Static items
      await _scanStaticItems(path);
      // Scan Shell Extensions
      await _scanShellExtensions(path);
    }

    // Filter duplicates and fetch icons
    final Map<String, ContextMenuItem> uniqueItems = <String, ContextMenuItem>{};
    for (final ContextMenuItem item in items) {
      final String key = "${item.type}_${item.registryPath}";
      if (!uniqueItems.containsKey(key)) {
        item.fetchIcon();
        uniqueItems[key] = item;
      }
    }

    setState(() {
      items = uniqueItems.values.toList();
      isLoading = false;
    });
  }

  RegistryKey? _openRegistryPath(String path) {
    try {
      return Registry.openPath(RegistryHive.classesRoot, path: path, desiredAccessRights: AccessRights.readOnly64);
    } catch (e) {
      return null;
    }
  }

  Future<void> _scanStaticItems(String basePath) async {
    final String shellPath = "$basePath\\shell";
    final RegistryKey? key = _openRegistryPath(shellPath);
    if (key == null) return;

    for (final String subkeyName in key.subkeyNames) {
      if (<String>["open", "print", "edit", "explore", "find", "runas", "runasuser", "openas", "printto"]
          .contains(subkeyName.toLowerCase())) {
        continue;
      }

      final RegistryKey? subkey = _openRegistryPath("$shellPath\\$subkeyName");
      if (subkey == null) continue;

      String name = subkey.getValueAsString("MUIVerb") ?? subkey.getValueAsString("") ?? subkeyName;
      if (name.startsWith("@")) {
        // Resource string, can be resolved with SHLoadIndirectString, but for now we skip or keep
        if (name.contains("shell32.dll") || name.contains("explorer.exe")) {
          subkey.close();
          continue;
        }
      }

      final String? command = subkey.getValueAsString("", path: "command");
      final String? iconSource = subkey.getValueAsString("Icon");
      final bool enabled = subkey.getValueAsString("LegacyDisable") == null;

      items.add(ContextMenuItem(
        name: name,
        registryPath: "$shellPath\\$subkeyName",
        hive: RegistryHive.classesRoot,
        type: ContextMenuItemType.static,
        isEnabled: enabled,
        command: command,
        iconSource: iconSource,
      ));

      subkey.close();
    }
    key.close();
  }

  Future<void> _scanShellExtensions(String basePath) async {
    final String handlerPath = "$basePath\\shellex\\ContextMenuHandlers";
    final RegistryKey? key = _openRegistryPath(handlerPath);
    if (key == null) return;

    for (final String subkeyName in key.subkeyNames) {
      final RegistryKey? subkey = _openRegistryPath("$handlerPath\\$subkeyName");
      if (subkey == null) continue;

      String? clsid = subkey.getValueAsString("");
      if (clsid == null || clsid.isEmpty) {
        clsid = subkeyName; // Some handlers use the key name as CLSID
      }

      final bool isEnabled = !clsid.startsWith("-");
      final String cleanClsid = isEnabled ? clsid : clsid.substring(1);

      // Try to find a better name from CLSID
      String name = subkeyName;
      String? iconSource;
      final RegistryKey? clsidKey = _openRegistryPath("CLSID\\$cleanClsid");
      if (clsidKey != null) {
        final String? clsidName = clsidKey.getValueAsString("");
        if (clsidName != null && clsidName.isNotEmpty) {
          name = clsidName;
        }
        iconSource = clsidKey.getValueAsString("", path: "DefaultIcon");
        clsidKey.close();
      }

      items.add(ContextMenuItem(
        name: name,
        registryPath: "$handlerPath\\$subkeyName",
        hive: RegistryHive.classesRoot,
        type: ContextMenuItemType.shellEx,
        isEnabled: isEnabled,
        clsid: cleanClsid,
        iconSource: iconSource,
      ));

      subkey.close();
    }
    key.close();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color background = globalSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!isAdmin) _buildAdminWarning(),
          _buildHeader(accent, background, onSurface),
          const SizedBox(height: 12),
          _buildTargetSelector(accent, onSurface),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (items.isNotEmpty)
            Expanded(child: _buildItemList(accent, onSurface))
          else if (!isLoading)
            const Expanded(child: Center(child: Text("No custom items found or scan required."))),
        ],
      ),
    );
  }

  Widget _buildAdminWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Not running as Administrator. You may not be able to modify some items.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => WinUtils.runAsAdmin(Platform.resolvedExecutable),
            child: const Text("Restart as Admin", style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text("Context Menu Cleaner", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text("Manage app-added context menu items.",
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.7))),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _scan,
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text("SCAN"),
        ),
      ],
    );
  }

  Widget _buildTargetSelector(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _buildTypeButton(ContextTarget.allFiles, "All Files", Icons.insert_drive_file_outlined),
              _buildTypeButton(ContextTarget.folder, "Folders", Icons.folder_outlined),
              _buildTypeButton(ContextTarget.directory, "Directory", Icons.snippet_folder_outlined),
              _buildTypeButton(ContextTarget.extension, "By Extension", Icons.extension_outlined),
            ],
          ),
          if (target == ContextTarget.extension) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: CustomTextInput(
                labelText: "Extension",
                value: extension,
                onChanged: (String val) => setState(() => extension = val),
                onSubmitted: (String val) {
                  setState(() => extension = val);
                  _scan();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeButton(ContextTarget type, String label, IconData icon) {
    final bool isSelected = target == type;
    final Color accent = globalSettings.themeColors.accentColor;
    return InkWell(
      onTap: () => setState(() => target = type),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? accent : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: isSelected ? accent : null),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : null)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(Color accent, Color onSurface) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 12),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final ContextMenuItem item = items[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onSurface.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: item.iconBytes != null
                    ? Image.memory(item.iconBytes!)
                    : Icon(Icons.apps_rounded, size: 18, color: onSurface.withValues(alpha: 0.3)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      item.type == ContextMenuItemType.static ? "Static Item" : "Shell Extension",
                      style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              CustomTooltip(
                message: item.isEnabled ? "Disable Item" : "Enable Item",
                child: Switch(
                  value: item.isEnabled,
                  onChanged: (bool val) async {
                    await item.toggle();
                    setState(() {});
                  },
                  activeThumbColor: accent,
                  activeTrackColor: accent.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
