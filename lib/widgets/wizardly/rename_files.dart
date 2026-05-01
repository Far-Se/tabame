// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/settings.dart';
import '../../pages/interface.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/mouse_scroll_widget.dart';
import '../widgets/text_input.dart';

class FileNameWidget extends StatefulWidget {
  const FileNameWidget({super.key});

  @override
  FileNameWidgetState createState() => FileNameWidgetState();
}

ValueNotifier<bool>? redrawWidget;

class FileNameWidgetState extends State<FileNameWidget> {
  String currentFolder = "";
  List<String> loadedFiles = <String>[];
  String infoText = "";
  bool filesHaveBeenLoaded = false;
  List<Filter> filters = <Filter>[];
  List<int> filtersError = <int>[];
  bool recursiveFolder = false;

  List<String> excludedFiles = <String>[];

  int hoveredIndex = -1;

  int totalMatched = 0;
  @override
  void initState() {
    super.initState();

    if (globalSettings.args.contains("-wizardly")) {
      currentFolder = globalSettings.args[0].replaceAll('"', '');
    }
    redrawWidget = ValueNotifier<bool>(false);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color background = globalSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(accent, background, onSurface),
          _buildOptionsBar(accent, onSurface),
          const SizedBox(height: 12),
          _buildFilterSection(accent, onSurface),
          if (filesHaveBeenLoaded) ...<Widget>[
            const SizedBox(height: 12),
            _buildResultsSection(accent, onSurface, background),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: _pickFolder,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: onSurface.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.drive_file_rename_outline_rounded, color: accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("Target Folder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            currentFolder.isEmpty
                                ? "Pick a folder to preview file renames"
                                : currentFolder.truncate(70, suffix: "..."),
                            style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _loadFiles,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: background,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.file_open_rounded, size: 18),
            label: const Text("SCAN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 220,
            child: CheckboxListTile(
              value: recursiveFolder,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text("Include subfolders", style: TextStyle(fontSize: 13)),
              onChanged: (bool? newValue) {
                recursiveFolder = newValue ?? false;
                setState(() {});
              },
            ),
          ),
          if (infoText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                infoText,
                style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text("Rename Rules", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 4),
                    Text(
                      "Build replacements with regex captures or switch to list replace for mapped values.",
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  filters.add(Filter(search: r"(\d)", replace: "[\$1]"));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text("Add Rule"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Tip: use groups like `(test)` and reference them in replace as `\$1`. Toggle `Tt` to switch to list replace.",
            style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6)),
          ),
          if (filters.isEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withValues(alpha: 0.06)),
              ),
              child: Text(
                "No rules yet. Add one to start shaping the new file names.",
                style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.55)),
              ),
            ),
          ...List<Widget>.generate(
              filters.length, (int index) => _buildFilterCard(index, filters[index], accent, onSurface)),
        ],
      ),
    );
  }

  Widget _buildFilterCard(int index, Filter filter, Color accent, Color onSurface) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              filtersError.contains(index) ? Colors.orange.withValues(alpha: 0.45) : onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      Text("${index + 1}", style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                filter.listReplace ? "List Replace" : "Regex Replace",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              if (filtersError.contains(index))
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: CustomTooltip(
                      message: "Regex Error", child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange)),
                ),
              _buildTinyIconButton(
                icon: Icons.text_fields_rounded,
                tooltip: filter.listReplace ? "Switch to text replace" : "Switch to list replace",
                active: filter.listReplace,
                accent: accent,
                onTap: () => setState(() => filter.listReplace = !filter.listReplace),
              ),
              if (filter.listReplace) ...<Widget>[
                const SizedBox(width: 6),
                _buildTinyIconButton(
                  icon: Icons.add_rounded,
                  tooltip: "Add mapping",
                  accent: accent,
                  onTap: () => setState(() => filter.replaceList.add(<String>["search", "replace"])),
                ),
                const SizedBox(width: 6),
                _buildTinyIconButton(
                  icon: Icons.calendar_month_outlined,
                  tooltip: "Load month names",
                  accent: accent,
                  onTap: () {
                    filter.replaceList = <List<String>>[
                      <String>["01", DateFormat('MMMM').format(DateTime.parse("2022-01-01"))],
                      <String>["02", DateFormat('MMMM').format(DateTime.parse("2022-02-01"))],
                      <String>["03", DateFormat('MMMM').format(DateTime.parse("2022-03-01"))],
                      <String>["04", DateFormat('MMMM').format(DateTime.parse("2022-04-01"))],
                      <String>["05", DateFormat('MMMM').format(DateTime.parse("2022-05-01"))],
                      <String>["06", DateFormat('MMMM').format(DateTime.parse("2022-06-01"))],
                      <String>["07", DateFormat('MMMM').format(DateTime.parse("2022-07-01"))],
                      <String>["08", DateFormat('MMMM').format(DateTime.parse("2022-08-01"))],
                      <String>["09", DateFormat('MMMM').format(DateTime.parse("2022-09-01"))],
                      <String>["10", DateFormat('MMMM').format(DateTime.parse("2022-10-01"))],
                      <String>["11", DateFormat('MMMM').format(DateTime.parse("2022-11-01"))],
                      <String>["12", DateFormat('MMMM').format(DateTime.parse("2022-12-01"))],
                    ];
                    setState(() {});
                  },
                ),
              ],
              const SizedBox(width: 6),
              _buildTinyIconButton(
                icon: Icons.close_rounded,
                tooltip: "Remove rule",
                onTap: () {
                  filters.remove(filter);
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: CustomTextInput(
                  labelText: "Search pattern",
                  value: filter.search,
                  onChanged: (String value) => setState(() => filter.search = value),
                  onUpdated: (String value) => setState(() => filter.search = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: filter.listReplace
                    ? _buildListReplaceEditor(filter, onSurface)
                    : CustomTextInput(
                        labelText: "Replace with",
                        value: filter.replace,
                        onChanged: (String value) => setState(() => filter.replace = value),
                        onUpdated: (String value) => setState(() => filter.replace = value),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListReplaceEditor(Filter filter, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: MouseRegion(
        onEnter: (PointerEnterEvent e) {
          if (filter.replaceList.length > 5) {
            mainScrollEnabled = false;
            context.findAncestorStateOfType<InterfaceState>()?.setState(() {});
          }
        },
        onExit: (PointerExitEvent e) {
          mainScrollEnabled = true;
          context.findAncestorStateOfType<InterfaceState>()?.setState(() {});
        },
        child: MouseScrollWidget(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<Widget>.generate(
                filter.replaceList.length,
                (int index) => Container(
                  width: 120,
                  margin: EdgeInsets.only(right: index == filter.replaceList.length - 1 ? 0 : 8),
                  child: Column(
                    children: <Widget>[
                      CustomTextInput(
                        key: UniqueKey(),
                        labelText: "Equals",
                        value: filter.replaceList[index][0],
                        onChanged: (String text) {
                          if (text == "") {
                            filter.replaceList.removeAt(index);
                          } else {
                            filter.replaceList[index][0] = text;
                          }
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      CustomTextInput(
                        key: UniqueKey(),
                        labelText: "Rename to",
                        value: filter.replaceList[index][1],
                        onChanged: (String text) => setState(() => filter.replaceList[index][1] = text),
                        onUpdated: (String text) => setState(() => filter.replaceList[index][1] = text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsSection(Color accent, Color onSurface, Color background) {
    totalMatched = 0;
    final List<_RenamePreview> previews = loadedFiles.reversed.map(_previewForFile).toList();
    final int changedCount = previews.where((_RenamePreview preview) => preview.oldName != preview.newName).length;
    final int selectedCount =
        previews.where((_RenamePreview preview) => preview.isSelected && preview.oldName != preview.newName).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text("Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 4),
                    Text("Review the generated names before applying changes.", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: selectedCount == 0
                    ? null
                    : () {
                        for (final _RenamePreview preview in previews) {
                          if (!preview.isSelected || preview.oldName == preview.newName) continue;
                          renameFile(preview.fullPath, preview.newName);
                        }
                        setState(() {});
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: background,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
                label: const Text("Rename Selected"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _buildStatPill("Files", "${loadedFiles.length}", Icons.folder_copy_outlined, accent, onSurface),
              _buildStatPill("Changed", "$changedCount", Icons.compare_arrows_rounded, Colors.orange, onSurface),
              _buildStatPill("Selected", "$selectedCount", Icons.check_circle_outline_rounded, Colors.green, onSurface),
              _buildStatPill("Matches", "$totalMatched", Icons.auto_fix_high_rounded, Colors.blue, onSurface),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: onSurface.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text("Current Name",
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.75))),
                ),
                Expanded(
                  child: Text("Preview Name",
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.75))),
                ),
                const SizedBox(width: 104),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...previews.map(
            (_RenamePreview preview) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTileFile(
                checkbox: preview.isSelected,
                oldName: preview.oldName,
                newName: preview.newName,
                onCheckPressed: (bool val) {
                  if (val == false) {
                    excludedFiles.add(preview.fullPath);
                  } else {
                    excludedFiles.remove(preview.fullPath);
                  }
                  setState(() {});
                },
                onRenamePressed: () {
                  renameFile(preview.fullPath, preview.newName);
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(color: onSurface, fontSize: 12),
              children: <InlineSpan>[
                TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: " $label", style: TextStyle(color: onSurface.withValues(alpha: 0.65))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTinyIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? accent,
    bool active = false,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return CustomTooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active && accent != null ? accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active && accent != null ? accent.withValues(alpha: 0.2) : onSurface.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 16, color: active && accent != null ? accent : onSurface.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    infoText = "";
    filesHaveBeenLoaded = false;
    if (mounted) setState(() {});

    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null) return;
    currentFolder = dir.path;

    if (mounted) setState(() {});
  }

  Future<void> _loadFiles() async {
    if (!Directory(currentFolder).existsSync()) return;
    loadedFiles.clear();
    excludedFiles.clear();

    final Stream<FileSystemEntity> stream = Directory(currentFolder)
        .list(recursive: recursiveFolder, followLinks: false)
        .handleError((dynamic e) => null, test: (dynamic e) => e is FileSystemException);
    await for (FileSystemEntity entity in stream) {
      loadedFiles.add(entity.path);
    }
    if (loadedFiles.length > 1000) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: SizedBox(
              height: 50,
              child: Center(
                child: Text(
                  "Too many files, maximum 1000 is recommended and you are trying to load ${loadedFiles.length}!",
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            actions: <Widget>[
              ElevatedButton(
                onPressed: () {
                  filesHaveBeenLoaded = true;
                  if (mounted) setState(() {});
                  Navigator.of(context).pop();
                },
                child: Text("Process", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text("Cancel", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            ],
          );
        },
      ).then((_) {});
      return;
    }
    filesHaveBeenLoaded = true;
    totalMatched = 0;
    if (mounted) setState(() {});
  }

  _RenamePreview _previewForFile(String loadedFile) {
    final String file = loadedFile.replaceFirst("${Directory(loadedFile).parent.path}\\", "");
    final String newFile = getNewFileName(file);
    return _RenamePreview(
      fullPath: loadedFile,
      oldName: file,
      newName: newFile,
      isSelected: !excludedFiles.contains(loadedFile),
    );
  }

  void renameFile(String fullPathFile, String newName) {
    final String path = Directory(fullPathFile).parent.path;
    final File file = File(fullPathFile);
    if (file.existsSync()) file.renameSync("$path\\$newName");
    loadedFiles[loadedFiles.indexOf(fullPathFile)] = "$path\\$newName";
  }

  String getNewFileName(String file) {
    String newFile = file;
    int fIndex = 0;
    for (Filter filter in filters) {
      if (filter.search.isEmpty) continue;
      try {
        final RegExp regex = RegExp(filter.search);
        if (regex.hasMatch(newFile)) {
          totalMatched++;
          newFile = newFile.replaceAllMapped(regex, (Match match) {
            String newString = "";
            if (filter.listReplace) {
              newString = match[0]!;
              for (int i = 1; i < match.groupCount + 1; i++) {
                final Iterable<List<String>> e =
                    filter.replaceList.where((List<String> element) => element[0] == match[i]);
                if (e.isNotEmpty) {
                  final String replaced = e.first[1];
                  newString = newString.replaceAll(match[1]!, replaced);
                }
              }
            } else {
              newString = filter.replace;
              for (int i = 1; i < match.groupCount + 1; i++) {
                newString = newString.replaceAll("\$$i", match[i]!);
              }
            }
            return newString;
          });
        }
        if (filtersError.contains(fIndex)) filtersError.remove(fIndex);
      } catch (e) {
        if (!filtersError.contains(fIndex)) filtersError.add(fIndex);
      }

      fIndex++;
    }
    return newFile;
  }
}

class ListTileFile extends StatefulWidget {
  final bool checkbox;
  final Function(bool) onCheckPressed;
  final Function() onRenamePressed;
  final String oldName;
  final String newName;
  const ListTileFile({
    super.key,
    required this.checkbox,
    required this.onCheckPressed,
    required this.onRenamePressed,
    required this.oldName,
    required this.newName,
  });

  @override
  ListTileFileState createState() => ListTileFileState();
}

class ListTileFileState extends State<ListTileFile> {
  bool showRename = false;
  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = globalSettings.themeColors.accentColor;
    final bool unchanged = widget.oldName == widget.newName;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onHover: (bool enter) {
        showRename = enter;
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: unchanged ? onSurface.withValues(alpha: 0.02) : accent.withValues(alpha: showRename ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: unchanged ? onSurface.withValues(alpha: 0.06) : accent.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              child: Checkbox(
                  value: unchanged ? false : widget.checkbox,
                  onChanged: (bool? e) => widget.onCheckPressed(e ?? false)),
            ),
            Expanded(
              child: Text(
                widget.oldName,
                style: TextStyle(
                  fontSize: 12,
                  color: unchanged ? onSurface.withValues(alpha: 0.45) : onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.newName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: unchanged ? FontWeight.w400 : FontWeight.w600,
                  color: unchanged ? onSurface.withValues(alpha: 0.45) : accent,
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: showRename && !unchanged ? 1 : 0.55,
                child: TextButton(
                  onPressed: unchanged ? null : () => widget.onRenamePressed(),
                  style: TextButton.styleFrom(
                    backgroundColor: unchanged ? onSurface.withValues(alpha: 0.04) : accent.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    unchanged ? "Same" : "Rename",
                    style: TextStyle(
                      color: unchanged ? onSurface.withValues(alpha: 0.45) : accent,
                      fontWeight: FontWeight.w600,
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
}

class _RenamePreview {
  final String fullPath;
  final String oldName;
  final String newName;
  final bool isSelected;

  const _RenamePreview({
    required this.fullPath,
    required this.oldName,
    required this.newName,
    required this.isSelected,
  });
}

class Filter {
  String search;
  String? _replace;
  String get replace => _replace!;
  set replace(String val) => _replace = val;
  bool listReplace = false;
  List<List<String>>? _replaceList;
  List<List<String>> get replaceList => _replaceList ?? <List<String>>[];
  set replaceList(List<List<String>> val) => _replaceList = val;
  Filter({required this.search, String? replace, this.listReplace = false, List<List<String>>? replaceList}) {
    _replaceList = replaceList ?? <List<String>>[];
    _replace = replace ?? "";
  }
}
