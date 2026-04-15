import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../itzy/quickmenu/button_window_app.dart';

class QuickmenuAppsCategoryEditor extends StatefulWidget {
  final int categoryIndex;

  const QuickmenuAppsCategoryEditor({
    super.key,
    required this.categoryIndex,
  });

  @override
  State<QuickmenuAppsCategoryEditor> createState() => _QuickmenuAppsCategoryEditorState();
}

class _QuickmenuAppsCategoryEditorState extends State<QuickmenuAppsCategoryEditor> {
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  tooltip: "Back to Apps",
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Edit Category",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          decoration: _inputDecoration(
                            context,
                            hintText: "Category name",
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: draft.viewType == AppCategoryViewType.grid ? "Grid view" : "List view",
                        onPressed: () {
                          setState(() {
                            draft.viewType = draft.viewType == AppCategoryViewType.grid ? AppCategoryViewType.list : AppCategoryViewType.grid;
                          });
                        },
                        icon: Icon(
                          draft.viewType == AppCategoryViewType.grid ? Icons.grid_view_rounded : Icons.view_agenda_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            draft.folderPath == null || draft.folderPath!.isEmpty ? "No sync folder selected" : draft.folderPath!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: _pickFolder,
                          child: const Text("Pick Folder"),
                        ),
                        if (draft.folderPath != null && draft.folderPath!.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => draft.folderPath = null),
                            child: const Text("Clear"),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          "Apps in Category",
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addFileToCategory,
                        icon: const Icon(Icons.file_open_outlined, size: 18),
                        label: const Text("Pick a file"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: draft.items.isEmpty
                        ? Center(
                            child: Text(
                              "This category is empty.",
                              style: theme.textTheme.bodySmall,
                            ),
                          )
                        : ReorderableListView.builder(
                            itemCount: draft.items.length,
                            buildDefaultDragHandles: false,
                            dragStartBehavior: DragStartBehavior.down,
                            onReorder: (int oldIndex, int newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final AppItem item = draft.items.removeAt(oldIndex);
                                draft.items.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (BuildContext context, int index) {
                              final AppItem item = draft.items[index];
                              return Container(
                                key: ValueKey<String>(item.path),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  leading: RepaintBoundary(
                                    child: WindowsAppButton(path: item.path),
                                  ),
                                  title: Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    item.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: Icon(
                                          Icons.drag_indicator_rounded,
                                          size: 18,
                                          color: theme.hintColor,
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip: "Remove",
                                        onPressed: () => _removeFromCategory(index),
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: _deleteCategory,
                        child: Text(
                          "Delete Category",
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          _save();
                          Navigator.of(context).pop(true);
                        },
                        child: const Text("Save"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hintText,
  }) {
    final ThemeData theme = Theme.of(context);
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surface.withValues(alpha: 0.34),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
