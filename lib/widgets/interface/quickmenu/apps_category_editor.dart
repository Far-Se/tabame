import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../itzy/quickmenu/button_window_app.dart';

class QMAppsCategoryEditor extends StatefulWidget {
  final int categoryIndex;

  const QMAppsCategoryEditor({
    super.key,
    required this.categoryIndex,
  });

  @override
  State<QMAppsCategoryEditor> createState() => _QMAppsCategoryEditorState();
}

class _QMAppsCategoryEditorState extends State<QMAppsCategoryEditor> {
  late List<AppCategory> categories;
  late AppCategory draft;
  late TextEditingController nameController;

  @override
  void initState() {
    super.initState();
    categories = List<AppCategory>.from(Boxes.appCategories);
    final AppCategory category = categories[widget.categoryIndex];
    draft = AppCategory(
      name: category.name,
      viewType: category.viewType,
      items: List<AppItem>.from(category.items),
      folderPath: category.folderPath,
      isCollapsed: category.isCollapsed,
    );
    nameController = TextEditingController(text: draft.name);
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  String _displayNameFromPath(String path) {
    final String filename = path.split('\\').last;
    return filename.replaceFirst(
      RegExp(r'\.(exe|lnk|url)$', caseSensitive: false),
      "",
    );
  }

  bool _containsPath(List<AppItem> items, String path) {
    return items.any((AppItem item) => item.path == path);
  }

  void _save() {
    draft.name = nameController.text.trim().isEmpty ? "Untitled Category" : nameController.text.trim();
    categories[widget.categoryIndex] = draft;
    Boxes.appCategories = categories;
  }

  void _pickFolder() {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select sync folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;
    setState(() => draft.folderPath = dir.path);
  }

  Future<void> _addFileToCategory() async {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Executables/Links': '*.exe;*.lnk;*.url',
        'All Files': '*.*',
      }
      ..defaultFilterIndex = 0
      ..defaultExtension = 'exe'
      ..title = 'Select a file';

    final File? result = file.getFile();
    if (result == null) return;

    final String path = result.path;
    if (_containsPath(draft.items, path)) return;

    setState(() {
      draft.items.add(
        AppItem(
          name: _displayNameFromPath(path),
          path: path,
        ),
      );
    });
  }

  void _removeFromCategory(int index) {
    draft.items.removeAt(index);
    setState(() {});
  }

  void _deleteCategory() {
    categories.removeAt(widget.categoryIndex);
    Boxes.appCategories = categories;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.settings_suggest_rounded, color: primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "CATEGORY PROPERTIES",
                      style: TextStyle(
                        fontSize: Design.baseFontSize,
                        fontWeight: FontWeight.w900,
                        color: primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      "Configure apps and synchronization rules",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        color: onSurface.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Basic Info
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: nameController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _modernInputDecoration(context, "Category Name", primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: onSurface.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: <Widget>[
                      _ViewTypeButton(
                        icon: Icons.grid_view_rounded,
                        label: "Grid",
                        isActive: draft.viewType == AppCategoryViewType.grid,
                        onTap: () => setState(() => draft.viewType = AppCategoryViewType.grid),
                      ),
                      _ViewTypeButton(
                        icon: Icons.view_agenda_rounded,
                        label: "List",
                        isActive: draft.viewType == AppCategoryViewType.list,
                        onTap: () => setState(() => draft.viewType = AppCategoryViewType.list),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sync Folder
          _buildSyncFolderSection(theme),
          const SizedBox(height: 16),

          // Apps List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    "CURATED ITEMS",
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      fontWeight: FontWeight.w800,
                      color: onSurface.withValues(alpha: 0.4),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${draft.items.length}",
                      style:
                          TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _addFileToCategory,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: primary,
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label:
                    Text("IMPORT FILE", style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Apps List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withValues(alpha: 0.05)),
              ),
              child: draft.items.isEmpty
                  ? _buildEmptyAppsState(theme)
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: draft.items.length,
                      buildDefaultDragHandles: false,
                      onReorderItem: (int oldIndex, int newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final AppItem item = draft.items.removeAt(oldIndex);
                          draft.items.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (BuildContext context, int index) {
                        return _AppItemTile(
                          key: ValueKey<String>("${draft.items[index].path}_$index"),
                          item: draft.items[index],
                          index: index,
                          onRemove: () => _removeFromCategory(index),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Footer
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: _deleteCategory,
                icon: Icon(Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.error),
                label: Text(
                  "DELETE CATEGORY",
                  style: TextStyle(
                      color: theme.colorScheme.error, fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "CANCEL",
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w800,
                      color: onSurface.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  _save();
                  Navigator.of(context).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text("SAVE CHANGES",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: Design.baseFontSize + 1)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncFolderSection(ThemeData theme) {
    final Color onSurface = theme.colorScheme.onSurface;
    final bool hasFolder = draft.folderPath != null && draft.folderPath!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasFolder ? theme.colorScheme.primary.withValues(alpha: 0.04) : onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFolder ? theme.colorScheme.primary.withValues(alpha: 0.15) : onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.folder_shared_outlined,
                    size: 14,
                    color: hasFolder ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "FOLDER SYNC",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: hasFolder ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.45),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (hasFolder)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => draft.folderPath = null),
                  icon: Icon(Icons.close_rounded, size: 14, color: onSurface.withValues(alpha: 0.3)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  !hasFolder ? "No sync folder assigned" : draft.folderPath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    fontFamily: "monospace",
                    color: hasFolder ? onSurface : onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _pickFolder,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: hasFolder
                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                            : onSurface.withValues(alpha: 0.1),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasFolder ? "CHANGE" : "SELECT",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: hasFolder ? theme.colorScheme.primary : onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAppsState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.layers_clear_outlined, size: 32, color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text(
            "This category is currently empty",
            style: TextStyle(
                fontSize: Design.baseFontSize + 1, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }

  InputDecoration _modernInputDecoration(BuildContext context, String label, Color accent) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08), width: 1)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.5)),
      filled: true,
      fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.015),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _ViewTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewTypeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
          decoration: BoxDecoration(
            color: isActive ? primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isActive ? primary.withValues(alpha: 0.2) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 14, color: isActive ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                  color: isActive ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppItemTile extends StatefulWidget {
  final AppItem item;
  final int index;
  final VoidCallback onRemove;

  const _AppItemTile({
    required super.key,
    required this.item,
    required this.index,
    required this.onRemove,
  });

  @override
  State<_AppItemTile> createState() => _AppItemTileState();
}

class _AppItemTileState extends State<_AppItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: _hovered ? primary.withValues(alpha: 0.05) : onSurface.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _hovered ? primary.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.05)),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: SizedBox(
            width: 28,
            height: 28,
            child: RepaintBoundary(child: WindowsAppButton(path: widget.item.path)),
          ),
          title: Text(
            widget.item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: _hovered ? primary : onSurface,
            ),
          ),
          subtitle: Text(
            widget.item.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Design.baseFontSize,
              fontFamily: "monospace",
              color: onSurface.withValues(alpha: 0.4),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_hovered)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: "Remove",
                  onPressed: widget.onRemove,
                  icon: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.error.withValues(alpha: 0.7)),
                ),
              ReorderableDragStartListener(
                index: widget.index,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: _hovered ? primary.withValues(alpha: 0.5) : onSurface.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
