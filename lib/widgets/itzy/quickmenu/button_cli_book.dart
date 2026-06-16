import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/panel_header.dart';

class CliBookButton extends StatelessWidget {
  const CliBookButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Cli Book", icon: const Icon(Icons.terminal_rounded), child: () => const CliBookWidget());
  }
}

class CliBookWidget extends StatefulWidget {
  const CliBookWidget({super.key});
  @override
  CliBookWidgetState createState() => CliBookWidgetState();
}

class CliBookWidgetState extends State<CliBookWidget> {
  List<CliBookCategory> cliBook = Boxes().cliBook;
  TextEditingController titleController = TextEditingController();
  TextEditingController messageController = TextEditingController();
  TextEditingController categoryNameController = TextEditingController();

  int categorySelected = -1;
  int memoSelected = -1;
  int runCategorySelected = -1;
  int runSelected = -1;
  int renamingCategoryIndex = -1;
  bool isReordering = false;
  final Map<String, TextEditingController> _variableControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _disposeVariableControllers();
    titleController.dispose();
    messageController.dispose();
    categoryNameController.dispose();
    super.dispose();
  }

  void _disposeVariableControllers() {
    for (final TextEditingController controller in _variableControllers.values) {
      controller.dispose();
    }
    _variableControllers.clear();
  }

  List<String> _extractVariables(String command) {
    final RegExp variableRegex = RegExp(r'\$\{([^}]+)\}');
    final Set<String> seen = <String>{};
    final List<String> variables = <String>[];

    for (final RegExpMatch match in variableRegex.allMatches(command)) {
      final String variable = (match.group(1) ?? "").trim();
      if (variable.isEmpty || seen.contains(variable)) continue;
      seen.add(variable);
      variables.add(variable);
    }

    return variables;
  }

  void _openEditor(int catIdx, int itemIdx) {
    runSelected = -1;
    runCategorySelected = -1;
    _disposeVariableControllers();
    categorySelected = catIdx;
    memoSelected = itemIdx;
    titleController.text = cliBook[categorySelected].items[memoSelected].key;
    messageController.text = cliBook[categorySelected].items[memoSelected].value;
    setState(() {});
  }

  void _closeEditor() {
    titleController.clear();
    messageController.clear();
    if (categorySelected != -1 && memoSelected != -1) {
      if (cliBook[categorySelected].items[memoSelected].key.isEmpty) {
        cliBook[categorySelected].items.removeAt(memoSelected);
        Boxes().cliBook = cliBook;
      }
    }
    categorySelected = -1;
    memoSelected = -1;
  }

  void _openRunView(int catIdx, int itemIdx) {
    memoSelected = -1;
    categorySelected = -1;
    titleController.clear();
    messageController.clear();
    _disposeVariableControllers();
    runCategorySelected = catIdx;
    runSelected = itemIdx;

    final String command = cliBook[runCategorySelected].items[runSelected].value;
    for (final String variable in _extractVariables(command)) {
      _variableControllers[variable] = TextEditingController();
    }

    setState(() {});
  }

  void _closeRunView() {
    runSelected = -1;
    runCategorySelected = -1;
    _disposeVariableControllers();
    setState(() {});
  }

  String _resolveVariables(String command) {
    return command.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (Match match) {
        final String variable = (match.group(1) ?? "").trim();
        return _variableControllers[variable]?.text ?? variable;
      },
    );
  }

  Future<void> _pickVariableFile(String variableName) async {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'All Files': '*.*'}
      ..defaultFilterIndex = 0
      ..title = 'Select any file';
    final File? result = file.getFile();
    if (result == null) return;

    _variableControllers[variableName]?.text = result.path;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickVariableFolder(String variableName) async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;

    _variableControllers[variableName]?.text = dir.path;
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _runSelectedItem({bool pickFolder = false}) async {
    if (runSelected == -1 || runCategorySelected == -1) return;
    final String resolvedCommand = _resolveVariables(cliBook[runCategorySelected].items[runSelected].value);
    if (resolvedCommand.trim().isEmpty) return;

    String? workingDirectory;
    if (pickFolder) {
      final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select Working Directory';
      final Directory? dir = dirPicker.getDirectory();
      if (dir == null || dir.path.isEmpty) return;
      workingDirectory = dir.path;
    }

    WinUtils.runPowerShellDetachedVisible(resolvedCommand, workingDirectory: workingDirectory, keepOpen: true);
  }

  Widget _buildInputDecorationField({
    required TextEditingController controller,
    required String hintText,
    required Color accent,
    required Color onSurface,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(fontSize: 13, color: onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 13, color: onSurface.withAlpha(100)),
        filled: true,
        fillColor: accent.withAlpha(10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
        ),
      ),
    );
  }

  Widget _buildRunView(Color accent, Color onSurface) {
    if (runSelected == -1 || runCategorySelected == -1) return const SizedBox();
    final CliBookItem item = cliBook[runCategorySelected].items[runSelected];
    final List<String> variables = _extractVariables(item.value);
    final String resolvedCommand = _resolveVariables(item.value);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (variables.isEmpty)
            Text(
              "This item does not use variables.",
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(140)),
            )
          else
            ...variables.map(
              (String variable) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    Widget variableField = TextField(
                      controller: _variableControllers[variable],
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 13, color: onSurface),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: variable,
                        hintStyle: TextStyle(fontSize: 13, color: onSurface.withAlpha(100)),
                        filled: true,
                        fillColor: accent.withAlpha(10),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          borderSide: BorderSide(color: accent.withAlpha(100), width: 1),
                        ),
                      ),
                    );

                    Widget actionButtons = Wrap(
                      spacing: 2,
                      runSpacing: 6,
                      children: <Widget>[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickVariableFile(variable),
                          icon: const Icon(Icons.file_open_rounded, size: 14),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickVariableFolder(variable),
                          icon: const Icon(Icons.folder_open_rounded, size: 14),
                        ),
                      ],
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(flex: 10, child: variableField),
                        const SizedBox(width: 8),
                        Expanded(flex: 4, child: actionButtons),
                      ],
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            "Preview",
            style: TextStyle(
                fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600, color: onSurface),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onSurface.withAlpha(20)),
            ),
            child: SelectableText(
              resolvedCommand,
              style: TextStyle(
                  fontSize: Design.baseFontSize + 2, height: 1.45, color: onSurface.withAlpha(200)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                onPressed: () => _openEditor(runCategorySelected, runSelected),
                tooltip: "Edit",
                icon: const Icon(Icons.edit_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: onSurface.withAlpha(20),
                  foregroundColor: onSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    onPressed: () => Clipboard.setData(ClipboardData(text: resolvedCommand)),
                    tooltip: "Copy",
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: onSurface.withAlpha(20),
                      foregroundColor: onSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _runSelectedItem(pickFolder: true),
                    tooltip: "Run in...",
                    icon: const Icon(Icons.folder_open_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: onSurface.withAlpha(20),
                      foregroundColor: onSurface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _runSelectedItem(pickFolder: false),
                    tooltip: "Run",
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addCategory() {
    setState(() {
      cliBook.add(CliBookCategory(name: "New Category", items: <CliBookItem>[]));
      renamingCategoryIndex = cliBook.length - 1;
      categoryNameController.text = "New Category";
      isReordering = true; // Show management controls so they can see the input clearly
      Boxes().cliBook = cliBook;
    });
  }

  void _renameCategory(int index) {
    setState(() {
      renamingCategoryIndex = index;
      categoryNameController.text = cliBook[index].name;
    });
  }

  void _saveCategoryName(int index) {
    setState(() {
      cliBook[index].name =
          categoryNameController.text.trim().isEmpty ? "Category" : categoryNameController.text.trim();
      renamingCategoryIndex = -1;
      Boxes().cliBook = cliBook;
    });
  }

  void _deleteCategory(int index) {
    if (cliBook[index].items.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text("Delete Category?", style: TextStyle(fontSize: 16)),
          content: Text("This will delete the category and all ${cliBook[index].items.length} items inside it."),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                setState(() {
                  cliBook.removeAt(index);
                  Boxes().cliBook = cliBook;
                });
                Navigator.pop(context);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      setState(() {
        cliBook.removeAt(index);
        Boxes().cliBook = cliBook;
      });
    }
  }

  Widget _buildCategory(int catIdx, Color accent, Color onSurface) {
    final CliBookCategory category = cliBook[catIdx];
    return Column(
      key: ValueKey<String>("cat_${category.name}_$catIdx"),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                category.isCollapsed = !category.isCollapsed;
                Boxes().cliBook = cliBook;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: BoxDecoration(
                color: accent.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withAlpha(25)),
              ),
              child: Row(
                children: <Widget>[
                  if (isReordering)
                    ReorderableDragStartListener(
                      index: catIdx,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.drag_indicator_rounded, size: 16, color: onSurface.withAlpha(100)),
                      ),
                    ),
                  AnimatedRotation(
                    turns: category.isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: renamingCategoryIndex == catIdx
                        ? TextField(
                            controller: categoryNameController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _saveCategoryName(catIdx),
                            onTapOutside: (_) => _saveCategoryName(catIdx),
                          )
                        : Text(
                            category.name,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onSurface),
                          ),
                  ),
                  if (isReordering) ...<Widget>[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _renameCategory(catIdx),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      tooltip: "Rename",
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteCategory(catIdx),
                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                      tooltip: "Delete",
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      category.items.add(CliBookItem(key: "", value: ""));
                      _openEditor(catIdx, category.items.length - 1);
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    tooltip: "Add Item to this category",
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!category.isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: category.items.length,
              onReorderItem: (int oldIdx, int newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx -= 1;
                  final CliBookItem item = category.items.removeAt(oldIdx);
                  category.items.insert(newIdx, item);
                  Boxes().cliBook = cliBook;
                });
              },
              itemBuilder: (BuildContext context, int itemIdx) {
                final CliBookItem item = category.items[itemIdx];
                return Padding(
                  key: ValueKey<String>("item_${catIdx}_${itemIdx}_${item.key}"),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: _CliBookItem(
                    name: item.key,
                    accent: accent,
                    onSurface: onSurface,
                    boldFont: true,
                    showDragHandle: isReordering,
                    dragIndex: itemIdx,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.value));
                    },
                    onRun: () => _openRunView(catIdx, itemIdx),
                    onEdit: () => _openEditor(catIdx, itemIdx),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header ──────────────────────────────────────────────
        if (runSelected != -1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accent.withAlpha(40),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: _closeRunView,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Run ${cliBook[runCategorySelected].items[runSelected].key}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (memoSelected != -1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accent.withAlpha(40),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => setState(_closeEditor),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cliBook[categorySelected].items[memoSelected].key.isEmpty ? "New Item" : "Edit Item",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    cliBook[categorySelected].items.removeAt(memoSelected);
                    memoSelected = -1;
                    categorySelected = -1;
                    Boxes().cliBook = cliBook;
                    setState(() {});
                  },
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: onSurface.withAlpha(150)),
                  splashRadius: 20,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          )
        else
          PanelHeader(
            title: "CliBook",
            icon: Icons.bookmark_rounded,
            extraActions: <Widget>[
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => isReordering = !isReordering),
                icon: Icon(isReordering ? Icons.check_rounded : Icons.reorder_rounded, size: 18),
                color: isReordering ? accent : onSurface.withAlpha(150),
                tooltip: "Rearrange",
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _addCategory,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                color: onSurface.withAlpha(150),
                tooltip: "New Category",
              ),
            ],
            buttonPressed: () {
              if (cliBook.isEmpty) {
                cliBook.add(CliBookCategory(name: "General", items: <CliBookItem>[]));
              }
              cliBook[0].items.add(CliBookItem(key: "", value: ""));
              cliBook[0].isCollapsed = false;
              _openEditor(0, cliBook[0].items.length - 1);
            },
            buttonIcon: Icons.add,
          ),
        // ── Scrollable Body ─────────────────────────────────────
        Flexible(
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Material(
              type: MaterialType.transparency,
              child: runSelected != -1
                  ? _buildRunView(accent, onSurface)
                  : memoSelected != -1
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _buildInputDecorationField(
                                controller: titleController,
                                hintText: "Title",
                                accent: accent,
                                onSurface: onSurface,
                              ),
                              const SizedBox(height: 12),
                              _buildInputDecorationField(
                                controller: messageController,
                                hintText: "Message / Command",
                                accent: accent,
                                onSurface: onSurface,
                                maxLines: 5,
                                minLines: 3,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: accent.withAlpha(10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: accent.withAlpha(30)),
                                ),
                                child: Text(
                                  r"Use ${varName} inside the command if this item needs values at run time. Example: cd ${projectFolder}",
                                  style: TextStyle(
                                      fontSize: Design.baseFontSize + 2,
                                      color: onSurface.withAlpha(160)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  cliBook[categorySelected].items[memoSelected].key = titleController.text;
                                  cliBook[categorySelected].items[memoSelected].value = messageController.text;
                                  Boxes().cliBook = cliBook;
                                  memoSelected = -1;
                                  categorySelected = -1;
                                  setState(() {});
                                },
                                style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                      backgroundColor: WidgetStateProperty.all(accent),
                                      foregroundColor: WidgetStateProperty.all(Colors.white),
                                    ),
                                child: Text("Save Changes",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.surface)),
                              ),
                            ],
                          ),
                        )
                      : cliBook.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.terminal_rounded, size: 48, color: onSurface.withAlpha(51)),
                                    const SizedBox(height: 16),
                                    Text(
                                      "No CLI Items",
                                      style: TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.bold, color: onSurface.withAlpha(200)),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Store your frequently used CLI commands and snippets here for quick access.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: Design.baseFontSize + 2,
                                          color: onSurface.withAlpha(128)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: cliBook.length,
                              buildDefaultDragHandles: false,
                              onReorderItem: (int oldIdx, int newIdx) {
                                setState(() {
                                  if (newIdx > oldIdx) newIdx -= 1;
                                  final CliBookCategory item = cliBook.removeAt(oldIdx);
                                  cliBook.insert(newIdx, item);
                                  Boxes().cliBook = cliBook;
                                });
                              },
                              itemBuilder: (BuildContext context, int index) {
                                return _buildCategory(index, accent, onSurface);
                              },
                            ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CliBookItem extends StatefulWidget {
  const _CliBookItem({
    required this.name,
    required this.accent,
    required this.onSurface,
    required this.boldFont,
    required this.onTap,
    required this.onRun,
    this.onEdit,
    this.showDragHandle = false,
    this.dragIndex,
  });
  final String name;
  final Color accent;
  final Color onSurface;
  final bool boldFont;
  final VoidCallback onTap;
  final VoidCallback onRun;
  final VoidCallback? onEdit;
  final bool showDragHandle;
  final int? dragIndex;

  @override
  State<_CliBookItem> createState() => _CliBookItemState();
}

class _CliBookItemState extends State<_CliBookItem> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _copied = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? Design.accent.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            widget.onTap();
            _copied = true;
            Timer(const Duration(seconds: 2), () {
              _copied = false;
              if (mounted) setState(() {});
            });
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                if (widget.showDragHandle && widget.dragIndex != null)
                  ReorderableDragStartListener(
                    index: widget.dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.drag_indicator_rounded, size: 14, color: widget.onSurface.withAlpha(100)),
                    ),
                  ),

                // Left accent bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _hovered ? 2.5 : 0,
                  height: 14,
                  margin: EdgeInsets.only(right: _hovered ? 7 : 0),
                  decoration: BoxDecoration(
                    color: Design.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 2),
                // Name
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 2,
                      fontWeight: widget.boldFont ? FontWeight.w500 : FontWeight.w300,
                      color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(200),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Copy icon on hover
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1.0 : 0.0,
                  child: _copied
                      ? Text("Copied!",
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              color: Design.accent.withAlpha(170)))
                      : Icon(Icons.copy, size: 13, color: Design.accent.withAlpha(170)),
                ),
                const SizedBox(width: 8),
                if (widget.onEdit != null)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 0.85 : 0.0,
                    child: InkWell(
                      onTap: widget.onEdit,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.edit_rounded, size: 13, color: widget.onSurface.withAlpha(180)),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 0.85 : 0.25,
                  child: InkWell(
                    onTap: widget.onRun,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.tune_rounded, size: 13, color: Design.accent.withAlpha(220)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
