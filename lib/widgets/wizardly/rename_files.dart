// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/settings.dart';
import '../../pages/interface.dart';
import '../widgets/info_text.dart';
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
    return Column(
      mainAxisAlignment: Maa.start,
      crossAxisAlignment: Caa.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: Maa.start,
          children: <Widget>[
            const SizedBox(width: 10),
            Flexible(
              flex: 5,
              fit: FlexFit.tight,
              child: ListTile(
                onTap: () async {
                  infoText = "";
                  filesHaveBeenLoaded = false;
                  if (mounted) setState(() {});

                  final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                  final Directory? dir = dirPicker.getDirectory();
                  if (dir == null) return;
                  currentFolder = dir.path;

                  if (mounted) setState(() {});
                },
                leading: const Icon(Icons.folder_copy_sharp),
                title: const Text("Pick a folder"),
                subtitle: currentFolder.isEmpty ? const InfoText("-") : InfoText(currentFolder.truncate(50, suffix: "...")),
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: ElevatedButton(
                onPressed: () async {
                  if (!Directory(currentFolder).existsSync()) return;
                  loadedFiles.clear();

                  Stream<FileSystemEntity> stream = Directory(currentFolder)
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
                          content: Container(
                              height: 50,
                              child: Center(
                                  child: Text("Too many files, maximum 1000 is recommended and you are trying to load ${loadedFiles.length}!",
                                      style: const TextStyle(fontSize: 20)))),
                          actions: <Widget>[
                            ElevatedButton(
                                onPressed: () {
                                  filesHaveBeenLoaded = true;
                                  if (mounted) setState(() {});
                                  Navigator.of(context).pop();
                                },
                                child: Text("Process", style: TextStyle(color: Theme.of(context).colorScheme.primary))),
                            ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(), child: Text("Cancel", style: TextStyle(color: Theme.of(context).colorScheme.primary))),
                          ],
                        );
                      },
                    ).then((_) {});
                    return;
                  }
                  filesHaveBeenLoaded = true;
                  totalMatched = 0;
                  if (mounted) setState(() {});
                },
                child: Text("Get Files", style: TextStyle(color: Color(globalSettings.theme.background))),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: CheckboxListTile(
                  value: recursiveFolder,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text("Show All files in subfolders."),
                  onChanged: (bool? newValue) {
                    recursiveFolder = newValue ?? false;
                    setState(() {});
                  }),
            ),
          ],
        ),
        if (infoText.isNotEmpty) ListTile(title: Text(infoText)),
        const Divider(height: 5, thickness: 1),
        ListTile(
          leading: const Icon(Icons.add),
          onTap: () {
            filters.add(Filter(search: r"(\d)", replace: "[\$1]"));
            setState(() {});
          },
          title: const Text("Add new Filter"),
        ),
        const Align(child: InfoText("Supports regex, add what you want to replace in brackets: ex : Search for : (test) Replace With: tset")),
        const Align(child: InfoText("Press in Tt to switch to List Replace")),
        // for (Filter filter in filters)
        ...List<Widget>.generate(filters.length, (int index) {
          final Filter filter = filters[index];
          return Row(
            mainAxisAlignment: Maa.start,
            crossAxisAlignment: Caa.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: InkWell(
                    onTap: () {
                      filters.remove(filter);
                      setState(() {});
                    },
                    child: const SizedBox(width: 20, child: Icon(Icons.close))),
              ),
              Container(
                // key: const ValueKey(0),
                constraints: const BoxConstraints(maxWidth: 200),
                child: TextInput(
                  labelText: "Search for:",
                  value: filter.search,
                  onChanged: (String value) => setState(() => filter.search = value),
                  onUpdated: (String value) => setState(() => filter.search = value),
                ),
              ),
              SizedBox(width: 5, child: !filtersError.contains(index) ? null : const Tooltip(message: "Regex Error", child: Icon(Icons.warning, size: 12))),
              filter.listReplace
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Column(
                        mainAxisAlignment: Maa.spaceEvenly,
                        crossAxisAlignment: Caa.center,
                        children: <Widget>[
                          InkWell(
                            onTap: () => setState(() => filter.listReplace = !filter.listReplace),
                            child: const Tooltip(message: "Text Replace", child: SizedBox(width: 20, child: Icon(Icons.text_fields))),
                          ),
                          InkWell(
                            onTap: () => setState(() => filter.replaceList.add(<String>["search", "replace"])),
                            child: const Tooltip(message: "Add\nTo Remove clear String Equals", child: SizedBox(width: 20, child: Icon(Icons.add))),
                          ),
                          InkWell(
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
                            child:
                                const Tooltip(message: "Predefined: Months", preferBelow: true, child: SizedBox(width: 20, child: Icon(Icons.calendar_month_outlined))),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: InkWell(
                          onTap: () => setState(() => filter.listReplace = !filter.listReplace),
                          child: const Tooltip(message: "Text Replace", child: SizedBox(width: 20, child: Icon(Icons.text_fields))))),
              if (!filter.listReplace)
                ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: TextInput(
                        labelText: "Replace With:",
                        value: filter.replace,
                        onChanged: (String value) => setState(() => filter.replace = value),
                        onUpdated: (String value) => setState(() => filter.replace = value)))
              else
                Expanded(
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
                      child: Row(
                        children: List<Widget>.generate(
                            filter.replaceList.length,
                            (int index) => SizedBox(
                                  width: 70,
                                  child: Column(
                                    children: <Widget>[
                                      TextInput(
                                          key: UniqueKey(),
                                          labelText: "String Equals",
                                          value: filter.replaceList[index][0],
                                          onChanged: (String text) {
                                            if (text == "") {
                                              filter.replaceList.removeAt(index);
                                            } else {
                                              filter.replaceList[index][0] = text;
                                            }
                                            setState(() {});
                                          }),
                                      TextInput(
                                          key: UniqueKey(),
                                          labelText: "Replace with",
                                          value: filter.replaceList[index][1],
                                          onChanged: (String text) => setState(() => filter.replaceList[index][1] = text),
                                          onUpdated: (String text) => setState(() => filter.replaceList[index][1] = text)),
                                    ],
                                  ),
                                )),
                      ),
                    ),
                  ),
                )
            ],
          );
        }),

        if (filesHaveBeenLoaded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Divider(height: 5, thickness: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text("Rename all Selected"),
                  onTap: () {
                    for (String file in loadedFiles) {
                      renameFile(file, getNewFileName(file.replaceFirst("${Directory(file).parent.path}\\", "")));
                    }
                    setState(() {});
                  },
                ),
                const Divider(height: 5, thickness: 1),
                ListView.builder(
                  shrinkWrap: true,
                  reverse: true,
                  itemCount: loadedFiles.length + 1,
                  prototypeItem: ListTileFile(
                    checkbox: false,
                    newName: '',
                    oldName: '',
                    onCheckPressed: (bool bool) {},
                    onRenamePressed: () {},
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) totalMatched = 0;
                    if (index == loadedFiles.length) {
                      return Align(alignment: Alignment.centerLeft, child: InfoText("  Total Matched matches: $totalMatched/${loadedFiles.length}"));
                    }
                    final String loadedFile = loadedFiles[loadedFiles.length - 1 - index];
                    final String file = loadedFile.replaceFirst("${Directory(loadedFile).parent.path}\\", "");
                    final String fullPathFile = loadedFile;
                    String newFile = getNewFileName(file);
                    return ListTileFile(
                      checkbox: !excludedFiles.contains(fullPathFile),
                      oldName: file,
                      newName: newFile,
                      onCheckPressed: (bool val) {
                        if (val == false) {
                          excludedFiles.add(fullPathFile);
                        } else {
                          excludedFiles.remove(fullPathFile);
                        }
                        setState(() {});
                      },
                      onRenamePressed: () {
                        renameFile(fullPathFile, newFile);
                        setState(() {});
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 20)
      ],
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
                final Iterable<List<String>> e = filter.replaceList.where((List<String> element) => element[0] == match[i]);
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
    return InkWell(
      onTap: () {},
      onHover: (bool enter) {
        showRename = enter;
        setState(() {});
      },
      child: Row(
        children: <Widget>[
          SizedBox(
            child: Checkbox(value: widget.oldName == widget.newName ? false : widget.checkbox, onChanged: (bool? e) => widget.onCheckPressed(e ?? false)),
          ),
          Expanded(
            child: widget.oldName == widget.newName ? InfoText(widget.oldName) : Text(widget.oldName),
          ),
          Expanded(
            child: widget.oldName == widget.newName ? InfoText(widget.newName) : Text(widget.newName),
          ),
          if (showRename && widget.oldName != widget.newName)
            SizedBox(
              width: 100,
              child: Align(
                child: TextButton(
                    onPressed: () => widget.onRenamePressed(),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                        if (states.contains(WidgetState.hovered)) {
                          return Theme.of(context).primaryColor.withOpacity(0.5);
                        }
                        return Colors.transparent;
                      }),
                    ),
                    child: const Text("Rename")),
              ),
            )
          else
            const SizedBox(width: 100)
          // else
          //   const SizedBox(width: 100)
        ],
      ),
    );
  }
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
