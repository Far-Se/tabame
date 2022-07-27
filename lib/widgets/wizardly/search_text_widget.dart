// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/classes/boxes.dart';
import '../../models/utils.dart';
import '../../models/win32/win32.dart';
import '../widgets/popup_dialog.dart';
import '../widgets/info_text.dart';
import '../widgets/text_box.dart';

class SearchTextWidget extends StatefulWidget {
  const SearchTextWidget({Key? key}) : super(key: key);

  @override
  SearchTextWidgetState createState() => SearchTextWidgetState();
}

class SearchTextWidgetState extends State<SearchTextWidget> {
  String currentFolder = r"E:\Projects\tabame\lib\";
  List<String> loadedFiles = <String>[];
  String infoText = "";

  int hoveredIndex = -1;

  String searchIncluded = "";
  String searchExcluded = r"node_modules;^.[a-z]";

  bool searchRecursively = true;
  bool searchUseRegex = false;
  String searchFor = "";
  bool searchRegexNewLine = false;
  bool searchCaseSensitive = false;
  bool searchMatchWholeWordOnly = false;
  final List<Occurance> allOccurances = <Occurance>[];
  String markdownOccurances = "";

  bool searchFinished = false;

  @override
  void initState() {
    final String? savedExcluded = Boxes.pref.getString("searchExcluded");
    if (savedExcluded != null) searchExcluded = savedExcluded;
    final String? savedIncluded = Boxes.pref.getString("searchIncluded");
    if (savedIncluded != null) searchIncluded = savedIncluded;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: Maa.start, crossAxisAlignment: Caa.stretch, children: <Widget>[
      Row(
        mainAxisAlignment: Maa.start,
        children: <Widget>[
          const SizedBox(width: 20),
          Flexible(
            flex: 5,
            fit: FlexFit.tight,
            child: ListTile(
              onTap: () async {
                infoText = "";
                searchFinished = false;
                if (mounted) setState(() {});

                final DirectoryPicker dirPicker = DirectoryPicker()
                  ..filterSpecification = <String, String>{'All Files': '*.*'}
                  ..defaultFilterIndex = 0
                  ..defaultExtension = 'exe'
                  ..title = 'Select any folder';
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
                if (searchFor.isEmpty) {
                  popupDialog(context, "First Specify what text you are looking for");
                  return;
                }
                if (!Directory(currentFolder).existsSync()) return;
                loadedFiles.clear();

                Stream<FileSystemEntity> stream = Directory(currentFolder)
                    .list(recursive: searchRecursively, followLinks: false)
                    .handleError((dynamic e) => null, test: (dynamic e) => e is FileSystemException);
                await for (FileSystemEntity entity in stream) {
                  loadedFiles.add(entity.path);
                }
                markdownOccurances = "";

                if (mounted) setState(() {});
                if (searchUseRegex) {
                  try {
                    RegExp(searchFor);
                  } catch (e) {
                    popupDialog(context, "Regex Failed!");
                    return;
                  }
                }
                startSearch((PingInfo total) {
                  if (mounted && total.totalFiles % 7 == 0) {
                    setState(() {
                      infoText = "Processed ${total.totalFiles} files and found ${allOccurances.length} matches";
                    });
                  }
                }).then((_) {
                  searchFinished = true;
                  if (mounted) setState(() {});
                });
              },
              child: Text("Search", style: TextStyle(color: Color(globalSettings.theme.background))),
            ),
          ),
        ],
      ),
      Row(
        children: <Widget>[
          Expanded(
            child: CheckboxListTile(
                value: searchRecursively,
                controlAffinity: ListTileControlAffinity.leading,
                dense: false,
                title: const Text("Recursive"),
                onChanged: (bool? newValue) => setState(() => searchRecursively = newValue ?? false)),
          ),
          Expanded(
            child: TextInput(
                hintText: "Separated by ';' ex: cpp;dart;js",
                labelText: "Include files with extension",
                value: searchIncluded,
                onChanged: (String e) {
                  Boxes.updateSettings("searchIncluded", e);
                  return searchIncluded = e;
                }),
          ),
          Expanded(
            child: TextInput(
                labelText: "Ignore these files/folders",
                value: searchExcluded,
                onChanged: (String e) {
                  Boxes.updateSettings("searchExcluded", e);
                  return searchExcluded = e;
                }),
          )
        ],
      ),
      if (infoText.isNotEmpty) ListTile(title: Text(infoText)),
      const Divider(thickness: 1, height: 5),
      Row(
        mainAxisAlignment: Maa.start,
        crossAxisAlignment: Caa.start,
        children: <Widget>[
          Expanded(
            child: ListTile(
              title: TextInput(
                labelText: "Search for:",
                onChanged: (String e) {
                  searchFor = e;
                },
              ),
            ),
          ),
          Expanded(
            child: Column(children: <Widget>[
              const SizedBox(height: 5),
              CheckBoxWidget(text: "Case Sensitive", value: searchCaseSensitive, onTap: (bool value) => setState(() => searchCaseSensitive = !searchCaseSensitive)),
              CheckBoxWidget(
                  text: "Match whole text only",
                  value: searchMatchWholeWordOnly,
                  onTap: (bool value) => setState(() => searchMatchWholeWordOnly = !searchMatchWholeWordOnly)),
            ]),
          ),
          Expanded(
            child: Column(mainAxisAlignment: Maa.start, crossAxisAlignment: Caa.start, children: <Widget>[
              const SizedBox(height: 5),
              CheckBoxWidget(text: "Use Regex", value: searchUseRegex, onTap: (bool value) => setState(() => searchUseRegex = !searchUseRegex)),
              if (searchUseRegex)
                CheckBoxWidget(text: ". Matches new Line", value: searchRegexNewLine, onTap: (bool value) => setState(() => searchRegexNewLine = !searchRegexNewLine)),
            ]),
          )
        ],
      ),
      const Divider(thickness: 1, height: 5),
      if (searchFinished)
        Markdown(
          // controller: controller,
          selectable: true,
          controller: ScrollController(),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,

          data: markdownOccurances == "" ? "No Occurances have been found!" : markdownOccurances,
          imageBuilder: (Uri uri, String? str1, String? str2) {
            final Map<String, IconData> icons = <String, IconData>{
              "tips": Icons.tips_and_updates,
              "remap": Icons.keyboard,
              "projects": Icons.folder_copy,
              "trktivty": Icons.celebration,
              "tasks": Icons.task_alt,
            };
            if (icons.containsKey(str2)) return Icon(icons[str2]);
            return const Icon(Icons.home);
          },
          onTapLink: (String str1, String? str2, String str3) {
            WinUtils.open(str1);
          },
        ),
    ]);
  }

  Future<void> startSearch(Function(PingInfo) ping) async {
    final List<String> included = searchIncluded.isNotEmpty ? searchIncluded.split(';') : <String>[];
    final List<String> excluded = searchExcluded.isNotEmpty ? searchExcluded.split(';') : <String>[];
    int totalProcessed = 0;
    for (String file in loadedFiles) {
      final String fileDirectory = Directory(file).parent.path;
      final String fileName = file.replaceAll("$fileDirectory\\", "");
      if (fileName.indexOf('.') < 1) continue;
      bool skip = false;
      for (String exclude in excluded) {
        if (exclude == "") continue;
        bool fromBegnning = false;

        if (exclude[0] == '^') {
          fromBegnning = true;
          exclude = exclude.substring(1);
        }
        // ignore: prefer_interpolation_to_compose_strings
        if (fileDirectory.contains(RegExp((fromBegnning ? "\\" : r"[^\\]") + exclude + r"[^\\]*\\", caseSensitive: false))) skip = true;
      }
      if (skip) continue;
      if (included.isNotEmpty) {
        skip = true;
        for (String include in included) {
          if (include == "") continue;
          if (fileName.contains(RegExp("$include\$", caseSensitive: false))) {
            skip = false;
          }
        }
        if (skip) continue;
      }
      final List<Occurance> occurances = searchUseRegex ? await searchInFileRegex(file) : await searchInFile(file);
      if (occurances.isNotEmpty) {
        for (Occurance occurance in occurances) {
          markdownOccurances += '''
${occurance.line}:${occurance.col} -> [${occurance.file}](${occurance.file}) :
```
${occurance.lines.join("\n").replaceAll("```", "\\`\\`\\`")}
```
''';
        }
      }
      allOccurances.addAll(occurances);
      totalProcessed++;
      ping(PingInfo(totalFiles: totalProcessed));
    }
  }

  Future<List<Occurance>> searchInFileRegex(String fileName) async {
    final List<Occurance> output = <Occurance>[];
    final File file = File(fileName);

    final Future<String> futureLines = file.readAsString().catchError((_) => "");
    final String fileString = await futureLines;

    final RegExp regex = RegExp(searchMatchWholeWordOnly ? "\\b$searchFor\\b" : searchFor, caseSensitive: searchCaseSensitive, dotAll: searchRegexNewLine);

    final Iterable<RegExpMatch> matches = regex.allMatches(fileString);
    for (RegExpMatch match in matches) {
      final List<String> lines = fileString.substring(0, match.start).split('\n');
      final int line = lines.length;
      final int col = lines.last.length + 1;
      final List<String> nextLines = fileString.substring(match.start, match.start + 500).split('\n');
      output.add(Occurance(file: fileName, col: col, line: line, lines: [
        lines.length == 1 ? "" : lines[lines.length - 2],
        lines.last + nextLines.first,
        nextLines.length == 1 ? "" : nextLines[1],
      ]));
    }

    return output;
  }

  Future<List<Occurance>> searchInFile(String fileName) async {
    String searchText = searchFor;
    if (!searchCaseSensitive) searchText = searchText.toLowerCase();
    final List<Occurance> output = <Occurance>[];
    final File file = File(fileName);

    // ignore: always_specify_types
    final Future<List<String>> futureLines = file.readAsLines().catchError((e) => <String>[""]);
    int i = 0;
    final List<String> fileLines = await futureLines;
    for (String line in fileLines) {
      final String originalLine = line;
      int index = -1;
      int ticks = 0;
      if (!searchCaseSensitive) line = line.toLowerCase();
      index = line.indexOf(searchText, index + 1);

      while (index > -1) {
        if (searchMatchWholeWordOnly) {
          final String before = index < 1 ? "!" : line.characters.elementAt(index - 1);
          final String after = index + searchFor.characters.length > line.length - 1 ? "!" : line.characters.elementAt(index + searchFor.characters.length);
          if (before.contains(RegExp(r'[a-z0-9_]')) || after.contains(RegExp(r'[a-z0-9_]'))) {
            index = line.indexOf(searchText, index + 1);
            continue;
          }
        }
        final List<String> lines = <String>[i > 0 ? fileLines[i - 1] : "", originalLine, i < fileLines.length - 1 ? fileLines[i + 1] : ""];
        output.add(Occurance(line: i, col: index, lines: lines, file: fileName));
        index = line.indexOf(searchText, index + 1);
        ticks++;
        if (ticks > 10000) break;
      }
      i++;
    }
    return output;
  }
}

class PingInfo {
  int totalFiles;
  PingInfo({required this.totalFiles});
}

class Occurance {
  String file;
  int line;
  int col;
  List<String> lines;
  Occurance({
    required this.file,
    required this.line,
    required this.col,
    required this.lines,
  });

  @override
  String toString() {
    return 'Occurance(file: $file, line: $line, col: $col, lines: $lines)';
  }
}

class CheckBoxWidget extends StatefulWidget {
  final Function(bool) onTap;
  final bool value;
  final String text;
  const CheckBoxWidget({
    Key? key,
    required this.onTap,
    required this.value,
    required this.text,
  }) : super(key: key);

  @override
  CheckBoxWidgetState createState() => CheckBoxWidgetState();
}

class CheckBoxWidgetState extends State<CheckBoxWidget> {
  bool checked = false;
  @override
  void initState() {
    checked = widget.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        checked = !checked;
        widget.onTap(checked);
      },
      child: Row(
        mainAxisAlignment: Maa.start,
        crossAxisAlignment: Caa.center,
        children: <Widget>[
          SizedBox(width: 25, child: Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: 18)),
          Expanded(child: Text(widget.text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
