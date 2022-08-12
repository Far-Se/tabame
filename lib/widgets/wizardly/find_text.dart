// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_text.dart';
import '../widgets/popup_dialog.dart';
import '../widgets/text_input.dart';

class SearchTextWidget extends StatefulWidget {
  const SearchTextWidget({Key? key}) : super(key: key);

  @override
  SearchTextWidgetState createState() => SearchTextWidgetState();
}

class SearchTextWidgetState extends State<SearchTextWidget> {
  List<String> loadedFiles = <String>[];
  String infoText = "";

  int searchState = 0;
  String searchFor = "";
  String searchFolder = "";
  String searchIncluded = "";
  String searchExcluded = "";
  bool searchFinished = false;
  bool searchUseRegex = false;
  bool searchRecursively = true;
  String markdownOccurrences = "";
  bool searchRegexNewLine = false;
  bool searchCaseSensitive = false;
  bool searchMatchWholeWordOnly = false;

  bool openInCode = false;

  @override
  void initState() {
    searchIncluded = Boxes.pref.getString("searchIncluded") ?? "";
    searchExcluded = Boxes.pref.getString("searchExcluded") ?? r"^\.[a-z];node_modules;build";
    openInCode = Boxes.pref.getBool("searchUseVSCode") ?? false;
    if (globalSettings.args.contains("-wizardly")) {
      searchFolder = globalSettings.args[0].replaceAll('"', '');
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: Maa.start, crossAxisAlignment: Caa.stretch, children: <Widget>[
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
                searchFinished = false;
                if (mounted) setState(() {});

                final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                final Directory? dir = dirPicker.getDirectory();
                if (dir == null) return;
                searchFolder = dir.path;

                if (mounted) setState(() {});
              },
              leading: const Icon(Icons.folder_copy_sharp),
              title: const Text("Pick a folder"),
              subtitle: searchFolder.isEmpty ? const InfoText("-") : InfoText(searchFolder.truncate(50, suffix: "...")),
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: ElevatedButton(
              onPressed: () async => initiateSearch(),
              child: Text(searchState == 0 ? "Search" : "Cancel", style: TextStyle(color: Color(globalSettings.theme.background))),
            ),
          ),
        ],
      ),
      Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Column(
                children: <Widget>[
                  CheckBoxWidget(value: searchRecursively, text: "Recursive", onChanged: (bool? newValue) => setState(() => searchRecursively = newValue ?? false)),
                  CheckBoxWidget(
                      value: openInCode,
                      text: "Open in VSCode",
                      onChanged: (bool? newValue) => setState(() {
                            Boxes.updateSettings("searchUseVSCode", newValue ?? false);
                            openInCode = newValue ?? false;
                          })),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextInput(
                hintText: "Separated by ';' ex: cpp;dart;js",
                labelText: "Include files with extension",
                value: searchIncluded,
                onChanged: (String e) {
                  Boxes.updateSettings("searchIncluded", e);
                  searchIncluded = e;
                }),
          ),
          Expanded(
            child: TextInput(
              labelText: "Ignore these files/folders",
              value: searchExcluded,
              onChanged: (String e) {
                Boxes.updateSettings("searchExcluded", e);
                searchExcluded = e;
              },
            ),
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
                onSubmitted: (String e) {
                  searchFor = e;
                  initiateSearch();
                },
              ),
            ),
          ),
          Expanded(
            child: Column(children: <Widget>[
              const SizedBox(height: 5),
              CheckBoxWidget(text: "Case Sensitive", value: searchCaseSensitive, onChanged: (bool value) => setState(() => searchCaseSensitive = !searchCaseSensitive)),
              CheckBoxWidget(
                  text: "Match whole text only",
                  value: searchMatchWholeWordOnly,
                  onChanged: (bool value) => setState(() => searchMatchWholeWordOnly = !searchMatchWholeWordOnly)),
            ]),
          ),
          Expanded(
            child: Column(mainAxisAlignment: Maa.start, crossAxisAlignment: Caa.start, children: <Widget>[
              const SizedBox(height: 5),
              CheckBoxWidget(text: "Use Regex", value: searchUseRegex, onChanged: (bool value) => setState(() => searchUseRegex = !searchUseRegex)),
              if (searchUseRegex)
                CheckBoxWidget(
                    text: ". Matches new Line", value: searchRegexNewLine, onChanged: (bool value) => setState(() => searchRegexNewLine = !searchRegexNewLine)),
            ]),
          )
        ],
      ),
      const Divider(thickness: 1, height: 5),
      if (searchFinished)
        Markdown(
          selectable: true,
          controller: ScrollController(),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          styleSheet: MarkdownStyleSheet(
              codeblockDecoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiary.withOpacity(0.1)),
              code: const TextStyle(backgroundColor: Colors.transparent)),
          data: markdownOccurrences == "" ? "No Occurances have been found!" : markdownOccurrences,
          onTapLink: (String str1, String? str2, String str3) {
            if (openInCode) {
              WinUtils.open("code", arguments: '--goto "$str1:$str3"');
            } else {
              WinUtils.open(str1);
            }
          },
        ),
    ]);
  }

  Future<void> startSearch(Function(PingInfo) ping) async {
    searchFinished = false;
    final List<String> included = searchIncluded.isNotEmpty ? searchIncluded.split(';') : <String>[];
    final List<String> excluded = searchExcluded.isNotEmpty ? searchExcluded.split(';') : <String>[];
    int totalProcessed = 0;
    int totalFound = 0;
    for (String file in loadedFiles) {
      if (searchState == 2) {
        searchState = 0;
        infoText = "";
        if (mounted) setState(() {});
        return;
      }
      final String fileDirectory = Directory(file).parent.path;
      final String fileName = file.replaceAll("$fileDirectory\\", "");
      if (!fileName.contains('.')) continue;
      bool skip = false;
      for (String exclude in excluded) {
        if (exclude == "") continue;
        if (exclude[0] == '^') {
          exclude = exclude.substring(1);
          if (file.contains(RegExp(r"\\" + exclude + r"[^\\]*\\", caseSensitive: false))) skip = true;
        } else if (exclude[0] == "/" || exclude[0] == r"\\") {
          exclude = exclude.substring(exclude[0] == "/" ? 1 : 2);
          if (file.replaceFirst(searchFolder, '').contains(RegExp(r"^\\" + exclude + r"[^\\]*\\", caseSensitive: false))) skip = true;
        } else if (file.contains(RegExp(r"[^\\]" + exclude + r"[^\\]*\\", caseSensitive: false))) {
          skip = true;
        } else {
          if (RegExp(exclude, caseSensitive: false).hasMatch(file)) {
            skip = true;
          }
        }
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
        for (Occurance occurrence in occurances) {
          markdownOccurrences += '''
${occurrence.line}:${occurrence.col} -> [${occurrence.file.replaceAll(r"\.", r"\\.")}](${occurrence.file} "${occurrence.line}:${occurrence.col}") :
```
${occurrence.lines.join("\n").replaceAll("```", "\\`\\`\\`")}
```
''';
        }
        totalFound += occurances.length;
      }
      totalProcessed++;
      ping(PingInfo(totalFiles: totalProcessed, totalFound: totalFound));
    }
    searchFinished = true;

    searchState = 0;
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
      output.add(Occurance(file: fileName, col: col, line: line, lines: <String>[
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
    int i = 1;
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

  Future<void> initiateSearch() async {
    if (searchState == 1) {
      searchState = 2;
      return;
    }
    if (searchFor.isEmpty) {
      popupDialog(context, "First Specify what text you are looking for");
      return;
    }
    if (!Directory(searchFolder).existsSync()) return;
    loadedFiles.clear();

    Stream<FileSystemEntity> stream =
        Directory(searchFolder).list(recursive: searchRecursively, followLinks: false).handleError((dynamic e) => null, test: (dynamic e) => e is FileSystemException);
    await for (FileSystemEntity entity in stream) {
      loadedFiles.add(entity.path);
    }
    markdownOccurrences = "";

    if (mounted) setState(() {});
    if (searchUseRegex) {
      try {
        RegExp(searchFor);
      } catch (e) {
        popupDialog(context, "Regex Failed!");
        return;
      }
    }
    searchState = 1;
    await startSearch((PingInfo total) {
      if (mounted && total.totalFiles % 7 == 0) {
        setState(() {
          infoText = "Processed ${total.totalFiles} files and found ${total.totalFound} matches";
        });
      }
    });
    if (mounted) setState(() {});
  }
}

class PingInfo {
  int totalFiles;
  int totalFound;
  PingInfo({
    required this.totalFiles,
    required this.totalFound,
  });
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
