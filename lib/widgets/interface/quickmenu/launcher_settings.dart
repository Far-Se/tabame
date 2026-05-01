import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/db/file_index_db.dart';
import '../../../services/file_indexer.dart';

class QuickmenuSearchSettings extends StatefulWidget {
  const QuickmenuSearchSettings({super.key});

  @override
  State<QuickmenuSearchSettings> createState() => _QuickmenuSearchSettingsState();
}

class _QuickmenuSearchSettingsState extends State<QuickmenuSearchSettings> {
  List<SearchFolder> _folders = <SearchFolder>[];
  int? _editingIndex;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _folders = List<SearchFolder>.from(Boxes.searchFolders);
  }

  void _save() {
    final List<SearchFolder> previousFolders = List<SearchFolder>.from(Boxes.searchFolders);
    final List<SearchFolder> nextFolders = List<SearchFolder>.from(_folders);

    Boxes.searchFolders = nextFolders;
    Boxes.updateSettings("searchFolders", nextFolders);
    if (mounted) setState(() {});

    unawaited(_syncSearchFolders(previousFolders, nextFolders));
  }

  Future<void> _syncSearchFolders(List<SearchFolder> previousFolders, List<SearchFolder> nextFolders) async {
    final Set<String> nextPaths = nextFolders.map((SearchFolder folder) => folder.path).toSet();
    for (final SearchFolder previousFolder in previousFolders) {
      if (!nextPaths.contains(previousFolder.path)) {
        await FileIndexer.instance.removeFolder(previousFolder.path);
      }
    }

    final List<SearchFolder> changedFolders =
        nextFolders.where((SearchFolder folder) => !previousFolders.contains(folder)).toList(growable: false);

    if (changedFolders.isEmpty) {
      await FileIndexer.instance.sync();
      return;
    }

    for (final SearchFolder folder in changedFolders) {
      await FileIndexer.instance.syncFolder(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            child: Column(
              children: <Widget>[
                if (_isAdding)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SearchFolderEditor(
                      onSaved: (SearchFolder folder) {
                        setState(() {
                          _folders.add(folder);
                          _isAdding = false;
                          _save();
                        });
                      },
                      onCancel: () => setState(() => _isAdding = false),
                    ),
                  ),
                ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
                      child: Opacity(opacity: 0.8, child: child),
                    );
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final SearchFolder folder = _folders[index];
                    final bool isEditing = _editingIndex == index;

                    if (isEditing) {
                      return Padding(
                        key: ValueKey<String>("edit_${folder.path}_$index"),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SearchFolderEditor(
                          initialFolder: folder,
                          onSaved: (SearchFolder updated) {
                            setState(() {
                              _folders[index] = updated;
                              _editingIndex = null;
                              _save();
                            });
                          },
                          onCancel: () => setState(() => _editingIndex = null),
                        ),
                      );
                    }

                    return _SearchFolderTile(
                      key: ValueKey<String>("${folder.path}_$index"),
                      folder: folder,
                      index: index,
                      isDimmed: _editingIndex != null || _isAdding,
                      onTap: () => setState(() {
                        _editingIndex = index;
                        _isAdding = false;
                      }),
                      onDelete: () => _confirmDelete(context, index),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "SEARCH INDEX",
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Prioritize folders for faster discovery",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: FileIndexer.instance.isIndexingNotifier,
                builder: (BuildContext context, bool isIndexing, _) {
                  return TextButton.icon(
                    onPressed: isIndexing ? null : () => FileIndexer.instance.fullReindex(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("Reindex All", style: TextStyle(fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => setState(() {
                  _isAdding = true;
                  _editingIndex = null;
                }),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text("Add Source", style: TextStyle(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: FileIndexer.instance.isIndexingNotifier,
            builder: (BuildContext context, bool isIndexing, Widget? child) {
              if (!isIndexing) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: <Widget>[
                      ValueListenableBuilder<bool>(
                        valueListenable: FileIndexer.instance.isCompletedNotifier,
                        builder: (BuildContext context, bool isCompleted, _) {
                          return SizedBox(
                            width: 16,
                            height: 16,
                            child: isCompleted
                                ? Icon(Icons.check_circle_outline_rounded, size: 18, color: theme.colorScheme.primary)
                                : const CircularProgressIndicator(strokeWidth: 2.5),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ValueListenableBuilder<bool>(
                              valueListenable: FileIndexer.instance.isCompletedNotifier,
                              builder: (BuildContext context, bool isCompleted, _) {
                                return Text(
                                  isCompleted ? "Indexing complete" : "Indexing folders...",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                );
                              },
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable: FileIndexer.instance.indexedCount,
                              builder: (BuildContext context, int count, _) {
                                return Text(
                                  "Processed $count items",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.hintColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    final SearchFolder folder = _folders[index];
    final ThemeData theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Remove Search Source?"),
        content: Text("Tabame will no longer index contents from:\n\n'${folder.path}'"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Keep it")),
          FilledButton(
            onPressed: () {
              setState(() {
                final SearchFolder folder = _folders.removeAt(index);
                FileIndexer.instance.removeFolder(folder.path);
                _save();
              });
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Confirm Removal"),
          ),
        ],
      ),
    );
  }
}

class _SearchFolderTile extends StatefulWidget {
  final SearchFolder folder;
  final int index;
  final bool isDimmed;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SearchFolderTile({
    required super.key,
    required this.folder,
    required this.index,
    required this.isDimmed,
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
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    return Opacity(
      opacity: widget.isDimmed ? 0.4 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isHovered ? 1.01 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: InkWell(
              onTap: widget.isDimmed ? null : widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isHovered ? primary.withValues(alpha: 0.1) : onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isHovered ? primary.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    // Order Badge / Drag Handle
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _isHovered ? primary.withValues(alpha: 0.2) : onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            "${widget.index + 1}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _isHovered ? primary : onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.folder.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: <Widget>[
                              _buildTag(
                                context,
                                widget.folder.includeFiles && widget.folder.includeFolders
                                    ? "Full"
                                    : (widget.folder.includeFiles ? "Files Only" : "Folders Only"),
                                Icons.category_rounded,
                              ),
                              if (widget.folder.allowedExtensions.isNotEmpty)
                                _buildTag(
                                  context,
                                  widget.folder.allowedExtensions.join(", "),
                                  Icons.extension_rounded,
                                ),
                              if (widget.folder.maxDepth != null)
                                _buildTag(
                                  context,
                                  "Depth: ${widget.folder.maxDepth}",
                                  Icons.unfold_more_rounded,
                                ),
                              ValueListenableBuilder<bool>(
                                valueListenable: FileIndexer.instance.isIndexingNotifier,
                                builder: (BuildContext context, bool isIndexing, _) {
                                  final int count = FileIndexDb.instance.getDescendantCount(widget.folder.path);
                                  if (count == 0 && isIndexing) return const SizedBox.shrink();
                                  return _buildTag(
                                    context,
                                    "$count items",
                                    Icons.folder_zip_outlined,
                                    color: theme.colorScheme.primary,
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Actions
                    if (_isHovered)
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.error),
                        onPressed: widget.onDelete,
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right_rounded, color: onSurface.withValues(alpha: 0.2)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String label, IconData icon, {Color? color}) {
    final ThemeData theme = Theme.of(context);
    final Color tagColor = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tagColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: tagColor.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: tagColor.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class SearchFolderEditor extends StatefulWidget {
  final SearchFolder? initialFolder;
  final void Function(SearchFolder folder) onSaved;
  final VoidCallback onCancel;

  const SearchFolderEditor({
    super.key,
    this.initialFolder,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<SearchFolderEditor> createState() => _SearchFolderEditorState();
}

class _SearchFolderEditorState extends State<SearchFolderEditor> {
  late SearchFolder _folder;
  late TextEditingController _pathController;
  late TextEditingController _extensionsController;
  late TextEditingController _depthController;

  @override
  void initState() {
    super.initState();
    _folder = widget.initialFolder?.copyWith() ??
        SearchFolder(path: "", includeFolders: true, includeFiles: true, allowedExtensions: <String>[]);
    _pathController = TextEditingController(text: _folder.path);
    _extensionsController = TextEditingController(text: _folder.allowedExtensions.join(", "));
    _depthController = TextEditingController(text: _folder.maxDepth?.toString() ?? "");
  }

  void _setExtensions(String extList) {
    final String combined = "${_extensionsController.text},$extList";
    final List<String> parts = combined
        .split(",")
        .map((String e) => e.trim().replaceAll(" ", ""))
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList();

    _extensionsController.text = parts.join(",");
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.5), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(color: primary.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.initialFolder == null ? "ADD SEARCH SOURCE" : "EDIT SEARCH SOURCE",
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          // Path
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: "Folder Path",
                    filled: true,
                    fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.folder_open_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: () {
                  final DirectoryPicker picker = DirectoryPicker()..title = "Select Source Folder";
                  final Directory? result = picker.getDirectory();
                  if (result != null) setState(() => _pathController.text = result.path);
                },
                icon: const Icon(Icons.add_home_work_rounded),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  minimumSize: const Size(54, 54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Switches
          Row(
            children: <Widget>[
              Expanded(
                child: _buildToggle(
                  "Include Files",
                  Icons.description_rounded,
                  _folder.includeFiles,
                  (bool v) => setState(() => _folder = _folder.copyWith(includeFiles: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildToggle(
                  "Include Folders",
                  Icons.folder_shared_rounded,
                  _folder.includeFolders,
                  (bool v) => setState(() => _folder = _folder.copyWith(includeFolders: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Extensions
          TextField(
            controller: _extensionsController,
            decoration: InputDecoration(
              labelText: "File Extensions (comma separated)",
              hintText: ".exe, .lnk, .dart",
              filled: true,
              fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.extension_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          // Presets
          Wrap(
            spacing: 8,
            children: <Widget>[
              _presetChip("🖼️ Images", ".jpg,.jpeg,.png,.webp,.gif"),
              _presetChip("⚙️ Apps", ".exe,.msi,.bat,.ps1,.lnk"),
              _presetChip("📄 Docs", ".pdf,.docx,.txt,.md,.rtf"),
              _presetChip("🎬 Video", ".mp4,.mkv,.avi,.mov"),
              _presetChip("💻 Code", ".dart,.js,.py,.cpp,.html"),
            ],
          ),
          const SizedBox(height: 16),
          // Depth
          TextField(
            controller: _depthController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Search Depth (Empty = Recursive)",
              hintText: "1 = This folder only",
              filled: true,
              fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.layers_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 24),
          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(onPressed: widget.onCancel, child: const Text("Discard")),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  if (_pathController.text.isEmpty) return;
                  final List<String> exts = _extensionsController.text
                      .split(",")
                      .map((String e) => e.trim())
                      .where((String e) => e.isNotEmpty)
                      .toList();
                  widget.onSaved(_folder.copyWith(
                    path: _pathController.text,
                    allowedExtensions: exts,
                    maxDepth: int.tryParse(_depthController.text),
                  ));
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text("Save Source", style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, String exts) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _setExtensions(exts),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildToggle(String label, IconData icon, bool value, Function(bool) onChanged) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : theme.colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? theme.colorScheme.primary.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon,
                size: 16,
                color: value ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: value ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            if (value) Icon(Icons.check_circle_rounded, size: 14, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
