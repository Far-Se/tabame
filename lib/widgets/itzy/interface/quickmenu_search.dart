import 'dart:convert';
import 'dart:io';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';

class QuickmenuSearchSettings extends StatefulWidget {
  const QuickmenuSearchSettings({super.key});

  @override
  State<QuickmenuSearchSettings> createState() => _QuickmenuSearchSettingsState();
}

class _QuickmenuSearchSettingsState extends State<QuickmenuSearchSettings> {
  List<SearchFolder> _folders = <SearchFolder>[];

  @override
  void initState() {
    super.initState();
    _folders = List<SearchFolder>.from(Boxes.searchFolders);
  }

  void _save() {
    Boxes.searchFolders = _folders;
    Boxes.updateSettings("searchFolders", jsonEncode(_folders.map((SearchFolder e) => e.toMap()).toList()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: _folders.length,
            onReorder: (int oldIndex, int newIndex) {
              setState(() {
                if (oldIndex < newIndex) newIndex -= 1;
                final SearchFolder item = _folders.removeAt(oldIndex);
                _folders.insert(newIndex, item);
                _save();
              });
            },
            proxyDecorator: (Widget child, int index, Animation<double> animation) {
              return Material(
                color: Colors.transparent,
                child: child,
              );
            },
            itemBuilder: (BuildContext context, int index) {
              final SearchFolder folder = _folders[index];
              return _SearchFolderTile(
                key: ValueKey<String>("${folder.path}_$index"),
                folder: folder,
                index: index,
                onTap: () => _showEditor(context, index),
                onDelete: () => _confirmDelete(context, index),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            "Search Folders",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
          IconButton(
            onPressed: () => _showEditor(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: "Add Search Folder",
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, [int? index]) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: SearchFolderEditor(
                key: UniqueKey(),
                folderIndex: index,
                onSaved: (SearchFolder folder) {
                  setState(() {
                    if (index != null) {
                      _folders[index] = folder;
                    } else {
                      _folders.add(folder);
                    }
                    _save();
                  });
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    final SearchFolder folder = _folders[index];
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Remove Search Folder"),
        content: Text("Are you sure you want to stop searching in '${folder.path}'?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              setState(() {
                _folders.removeAt(index);
                _save();
              });
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }
}

class _SearchFolderTile extends StatefulWidget {
  final SearchFolder folder;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SearchFolderTile({
    required super.key,
    required this.folder,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SearchFolderTile> createState() => _SearchFolderTileState();
}

class _SearchFolderTileState extends State<_SearchFolderTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _isHovered = true),
      onExit: (PointerExitEvent _) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withAlpha(_isHovered ? 60 : 20),
            width: 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _isHovered ? colorScheme.primary.withAlpha(8) : Colors.transparent,
              ),
              child: Row(
                children: <Widget>[
                  // Drag Handle
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Container(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Icon(Icons.drag_indicator_rounded, size: 20, color: colorScheme.onSurface.withAlpha(100)),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.folder_rounded, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.folder.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _isHovered ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            _buildMiniTag(
                              context,
                              "${widget.folder.includeFolders ? 'Folders' : ''}${widget.folder.includeFolders && widget.folder.includeFiles ? ' & ' : ''}${widget.folder.includeFiles ? 'Files' : ''}",
                              Icons.category_outlined,
                            ),
                            if (widget.folder.allowedExtensions.isNotEmpty)
                              _buildMiniTag(
                                context,
                                widget.folder.allowedExtensions.join(", "),
                                Icons.extension_outlined,
                              ),
                            if (widget.folder.maxDepth != null)
                              _buildMiniTag(
                                context,
                                "Depth: ${widget.folder.maxDepth}",
                                Icons.unfold_more_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Hover Actions
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: IconButton(
                      tooltip: "Remove",
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error.withAlpha(200)),
                      onPressed: widget.onDelete,
                      splashRadius: 20,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _isHovered ? colorScheme.primary : colorScheme.onSurface.withAlpha(80),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTag(BuildContext context, String text, IconData icon) {
    final Color color = Theme.of(context).colorScheme.onSurface.withAlpha(120);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

class SearchFolderEditor extends StatefulWidget {
  final int? folderIndex;
  final void Function(SearchFolder folder) onSaved;

  const SearchFolderEditor({
    super.key,
    this.folderIndex,
    required this.onSaved,
  });

  @override
  State<SearchFolderEditor> createState() => _SearchFolderEditorState();
}

class _SearchFolderEditorState extends State<SearchFolderEditor> {
  late SearchFolder folder;
  late TextEditingController pathController;
  late TextEditingController extensionsController;
  late TextEditingController depthController;

  @override
  void initState() {
    super.initState();
    if (widget.folderIndex != null) {
      folder = Boxes.searchFolders[widget.folderIndex!].copyWith();
    } else {
      folder = SearchFolder(path: "", includeFolders: true, includeFiles: true, allowedExtensions: <String>[]);
    }
    pathController = TextEditingController(text: folder.path);
    extensionsController = TextEditingController(text: folder.allowedExtensions.join(", "));
    depthController = TextEditingController(text: folder.maxDepth?.toString() ?? "");
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(theme),
        const SizedBox(height: 24),
        _buildPathInput(theme),
        const SizedBox(height: 16),
        _buildIncludeSwitches(theme),
        const SizedBox(height: 16),
        _buildExtensionsInput(theme),
        const SizedBox(height: 16),
        _buildDepthInput(theme),
        const SizedBox(height: 32),
        _buildActionButtons(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: <Widget>[
        Icon(Icons.create_new_folder_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          widget.folderIndex != null ? "Edit Folder" : "Add Folder",
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildPathInput(ThemeData theme) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: pathController,
            decoration: InputDecoration(
              labelText: "Folder Path",
              hintText: "C:\\Users\\...",
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              ),
              prefixIcon: const Icon(Icons.folder_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () {
            final DirectoryPicker picker = DirectoryPicker()..title = "Select Search Folder";
            final Directory? result = picker.getDirectory();
            if (result != null) {
              setState(() => pathController.text = result.path);
            }
          },
          icon: const Icon(Icons.folder_open_rounded),
          tooltip: "Browse",
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(56, 56),
          ),
        ),
      ],
    );
  }

  Widget _buildIncludeSwitches(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          SwitchListTile(
            title: const Text("Include Subfolders"),
            secondary: const Icon(Icons.folder_shared_outlined),
            value: folder.includeFolders,
            onChanged: (bool v) => setState(() => folder = folder.copyWith(includeFolders: v)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text("Include Files"),
            secondary: const Icon(Icons.description_outlined),
            value: folder.includeFiles,
            onChanged: (bool v) => setState(() => folder = folder.copyWith(includeFiles: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionsInput(ThemeData theme) {
    return TextField(
      controller: extensionsController,
      decoration: InputDecoration(
        labelText: "File Extensions",
        hintText: ".exe, .lnk (leave empty for all)",
        helperText: "Comma separated list with dots",
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        prefixIcon: const Icon(Icons.extension_rounded),
      ),
    );
  }

  Widget _buildDepthInput(ThemeData theme) {
    return TextField(
      controller: depthController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: "Search Depth",
        hintText: "Empty for recursive",
        helperText: "1 = this folder only, 2 = one subfolder level",
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        prefixIcon: const Icon(Icons.layers_outlined),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {
            if (pathController.text.isEmpty) return;
            final List<String> exts = extensionsController.text
                .split(",")
                .map((String e) => e.trim())
                .where((String e) => e.isNotEmpty)
                .toList();
            widget.onSaved(folder.copyWith(
              path: pathController.text,
              allowedExtensions: exts,
              maxDepth: int.tryParse(depthController.text),
            ));
          },
          icon: const Icon(Icons.check_rounded),
          label: Text(widget.folderIndex != null ? "Save Changes" : "Add Folder"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
