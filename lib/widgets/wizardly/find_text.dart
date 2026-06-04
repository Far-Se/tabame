// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/popup_dialog.dart';
import '../widgets/text_input.dart';

class SearchTextWidget extends StatefulWidget {
  const SearchTextWidget({super.key});

  @override
  SearchTextWidgetState createState() => SearchTextWidgetState();
}

class SearchTextWidgetState extends State<SearchTextWidget> {
  final ScrollController _scrollController = ScrollController();

  Map<String, List<Occurance>> groupedResults = <String, List<Occurance>>{};
  List<String> loadedFiles = <String>[];
  String infoText = "";

  int searchState = 0; // 0: Idle, 1: Searching, 2: Cancelled
  bool searchFinished = false;

  String searchString = "";
  String includedString = "";
  String excludedString = "";

  bool searchUseRegex = false;
  bool searchRecursively = true;
  bool searchRegexNewLine = false;
  bool searchCaseSensitive = false;
  bool searchMatchWholeWordOnly = false;
  bool openInCode = false;
  String searchFolder = "";

  @override
  void initState() {
    super.initState();
    includedString = Boxes.pref.getString("searchIncluded") ?? "";
    excludedString = Boxes.pref.getString("searchExcluded") ?? r"^\.[a-z];node_modules;build";
    openInCode = Boxes.pref.getBool("searchUseVSCode") ?? false;
    if (userSettings.args.contains("-wizardly")) {
      searchFolder = userSettings.args[0].replaceAll('"', '');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color background = userSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final List<String> filesWithMatches = groupedResults.keys.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          SliverToBoxAdapter(child: _buildHeader(accent, background, onSurface)),
          SliverToBoxAdapter(child: _buildOptionsBar(accent, onSurface)),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(child: _buildSearchCard(accent, onSurface)),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // Results Header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border.all(color: onSurface.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text("Search Results", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(
                          searchFinished
                              ? "Found ${groupedResults.length} files matching your query."
                              : (searchState == 1 ? "Search in progress..." : "No active search."),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (infoText.isNotEmpty)
                    _buildStatPill("Status", infoText, Icons.info_outline_rounded, accent, onSurface),
                ],
              ),
            ),
          ),

          // Results Content
          if (searchState == 1 && groupedResults.isEmpty)
            const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())))
          else if (searchFinished && groupedResults.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Container(
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  border: Border.all(color: onSurface.withValues(alpha: 0.08)),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.search_off_rounded, size: 48, color: onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      const Text("No matches found", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverMainAxisGroup(
              slivers: <Widget>[
                SliverToBoxAdapter(
                    child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                            color: onSurface.withValues(alpha: 0.03),
                            border: Border(
                              left: BorderSide(color: onSurface.withValues(alpha: 0.08)),
                              right: BorderSide(color: onSurface.withValues(alpha: 0.08)),
                            )))),
                SliverPadding(
                  padding: EdgeInsets.zero,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) {
                        final String filePath = filesWithMatches[index];
                        final List<Occurance> matches = groupedResults[filePath]!;
                        final bool isLast = index == filesWithMatches.length - 1;

                        return Container(
                          decoration: BoxDecoration(
                            color: onSurface.withValues(alpha: 0.03),
                            border: Border(
                              left: BorderSide(color: onSurface.withValues(alpha: 0.08)),
                              right: BorderSide(color: onSurface.withValues(alpha: 0.08)),
                              bottom: isLast ? BorderSide(color: onSurface.withValues(alpha: 0.08)) : BorderSide.none,
                            ),
                            borderRadius:
                                isLast ? const BorderRadius.vertical(bottom: Radius.circular(14)) : BorderRadius.zero,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: _FileResultCard(
                            filePath: filePath,
                            matches: matches,
                            accent: accent,
                            openInCode: openInCode,
                            searchTerm: searchString,
                            isRegex: searchUseRegex,
                          ),
                        );
                      },
                      childCount: filesWithMatches.length,
                    ),
                  ),
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    final bool isSearching = searchState == 1;
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
                    Icon(Icons.find_in_page_rounded, color: accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("Source Directory", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            searchFolder.isEmpty
                                ? "Pick a folder to search within"
                                : searchFolder.truncate(70, suffix: "..."),
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
            onPressed: initiateSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: isSearching ? Colors.redAccent : accent,
              foregroundColor: background,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: isSearching
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search_rounded, size: 20),
            label: Text(isSearching ? "CANCEL" : "SEARCH",
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          CheckBoxWidget(
              text: "Subfolders",
              value: searchRecursively,
              onChanged: (bool v) => setState(() => searchRecursively = v)),
          CheckBoxWidget(
              text: "Case Sensitive",
              value: searchCaseSensitive,
              onChanged: (bool v) => setState(() => searchCaseSensitive = v)),
          CheckBoxWidget(
              text: "Whole Word",
              value: searchMatchWholeWordOnly,
              onChanged: (bool v) => setState(() => searchMatchWholeWordOnly = v)),
          CheckBoxWidget(
            text: "Open in VSCode",
            value: openInCode,
            onChanged: (bool v) => setState(() {
              openInCode = v;
              Boxes.updateSettings("searchUseVSCode", v);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                    Text("Search Parameters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text("Specify what to find and which files to look into.", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              CheckBoxWidget(
                  text: "Use Regex", value: searchUseRegex, onChanged: (bool v) => setState(() => searchUseRegex = v)),
              if (searchUseRegex) ...<Widget>[
                const SizedBox(width: 12),
                CheckBoxWidget(
                    text: "Dot Match All",
                    value: searchRegexNewLine,
                    onChanged: (bool v) => setState(() => searchRegexNewLine = v)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          CustomTextInput(
            labelText: "Find text...",
            hintText: "Enter the text or pattern you are looking for",
            value: searchString,
            onChanged: (String val) => searchString = val,
            onSubmitted: (_) => initiateSearch(),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: CustomTextInput(
                  labelText: "Included Extensions",
                  hintText: "e.g., .dart; .js (leave empty for all)",
                  value: includedString,
                  onChanged: (String val) {
                    includedString = val;
                    Boxes.updateSettings("searchIncluded", val);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextInput(
                  labelText: "Excluded Paths",
                  hintText: "e.g., node_modules; build",
                  value: excludedString,
                  onChanged: (String val) {
                    excludedString = val;
                    Boxes.updateSettings("searchExcluded", val);
                  },
                ),
              ),
            ],
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

  Future<void> _pickFolder() async {
    infoText = "";
    searchFinished = false;
    if (mounted) setState(() {});

    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select target folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null) return;
    searchFolder = dir.path;
    if (mounted) setState(() {});
  }

  Future<void> startSearch(Function(PingInfo) ping) async {
    searchFinished = false;
    final List<String> included = includedString.isNotEmpty ? includedString.split(';') : <String>[];
    final List<String> excluded = excludedString.isNotEmpty ? excludedString.split(';') : <String>[];
    int totalProcessed = 0;
    int totalFound = 0;

    for (String file in loadedFiles) {
      if (searchState == 2) {
        searchState = 0;
        infoText = "Cancelled";
        if (mounted) setState(() {});
        return;
      }

      final String fileName = file.split(Platform.pathSeparator).last;
      if (!fileName.contains('.')) continue;

      bool skip = false;
      for (String exclude in excluded) {
        if (exclude.trim().isEmpty) continue;
        if (file.toLowerCase().contains(exclude.trim().toLowerCase())) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      if (included.isNotEmpty) {
        skip = true;
        for (String include in included) {
          if (include.trim().isEmpty) continue;
          if (fileName.toLowerCase().endsWith(include.trim().toLowerCase())) {
            skip = false;
            break;
          }
        }
        if (skip) continue;
      }

      final List<Occurance> occurances = await _searchInFile(file, searchString);

      if (occurances.isNotEmpty) {
        groupedResults[file] = occurances;
        totalFound += occurances.length;
        if (mounted) setState(() {});
      }
      totalProcessed++;

      if (totalProcessed % 20 == 0) {
        ping(PingInfo(totalFiles: totalProcessed, totalFound: totalFound));
      }
    }
    searchFinished = true;
    searchState = 0;
    infoText = "Found $totalFound matches";
  }

  Future<List<Occurance>> _searchInFile(String fileName, String searchFor) async {
    final List<Occurance> output = <Occurance>[];
    try {
      final File file = File(fileName);
      final String content = await file.readAsString().catchError((_) => "");
      if (content.isEmpty) return output;

      String pattern = searchUseRegex ? searchFor : RegExp.escape(searchFor);
      if (searchMatchWholeWordOnly) {
        pattern = "\\b$pattern\\b";
      }

      final RegExp regex = RegExp(
        pattern,
        caseSensitive: searchCaseSensitive,
        dotAll: searchRegexNewLine,
        multiLine: true,
      );

      final Iterable<RegExpMatch> matches = regex.allMatches(content);
      final List<String> contentLines = content.split('\n');

      for (RegExpMatch match in matches) {
        int currentPos = 0;
        int lineIdx = 0;
        for (int i = 0; i < contentLines.length; i++) {
          if (currentPos + contentLines[i].length >= match.start) {
            lineIdx = i;
            break;
          }
          currentPos += contentLines[i].length + 1;
        }

        final int col = match.start - currentPos + 1;
        final List<String> contextLines = <String>[
          if (lineIdx > 0) contentLines[lineIdx - 1],
          contentLines[lineIdx],
          if (lineIdx < contentLines.length - 1) contentLines[lineIdx + 1],
        ];

        output.add(Occurance(col: col, line: lineIdx + 1, lines: contextLines));
        if (output.length > 500) break;
      }
    } catch (e) {
      // Binary files or errors
    }
    return output;
  }

  Future<void> initiateSearch() async {
    if (searchState == 1) {
      searchState = 2;
      return;
    }

    if (searchString.isEmpty) {
      popupDialog(context, "Please enter a search term");
      return;
    }

    if (searchFolder.isEmpty || !Directory(searchFolder).existsSync()) {
      popupDialog(context, "Please select a valid folder");
      return;
    }

    groupedResults.clear();
    loadedFiles.clear();
    searchFinished = false;
    infoText = "Scanning...";
    if (mounted) setState(() {});

    try {
      if (searchUseRegex) {
        RegExp(searchString);
      }
    } catch (e) {
      popupDialog(context, "Invalid Regex Pattern");
      return;
    }

    Stream<FileSystemEntity> stream =
        Directory(searchFolder).list(recursive: searchRecursively, followLinks: false).handleError((dynamic e) => null);

    await for (FileSystemEntity entity in stream) {
      if (entity is File) {
        loadedFiles.add(entity.path);
      }
    }

    searchState = 1;
    await startSearch((PingInfo total) {
      if (mounted) {
        setState(() {
          infoText = "${total.totalFiles} checked";
        });
      }
    });

    if (mounted) setState(() {});
  }
}

class _FileResultCard extends StatefulWidget {
  final String filePath;
  final List<Occurance> matches;
  final Color accent;
  final bool openInCode;
  final String searchTerm;
  final bool isRegex;

  const _FileResultCard({
    required this.filePath,
    required this.matches,
    required this.accent,
    required this.openInCode,
    required this.searchTerm,
    required this.isRegex,
  });

  @override
  State<_FileResultCard> createState() => _FileResultCardState();
}

class _FileResultCardState extends State<_FileResultCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final String fileName = widget.filePath.split(Platform.pathSeparator).last;
    final String parentDir = widget.filePath.substring(0, widget.filePath.length - fileName.length);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: onSurface.withValues(alpha: 0.12)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Icon(_isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                      color: onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(parentDir.truncate(80, suffix: "..."),
                            style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: userSettings.themeColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text("${widget.matches.length} matches",
                        style: TextStyle(
                            color: userSettings.themeColors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  _buildTinyIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: widget.openInCode ? "Open in VSCode" : "Open File",
                    onTap: _openFile,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.02),
                border: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.05))),
              ),
              child: Column(
                children: widget.matches.map((Occurance m) => _buildOccurrenceTile(m, onSurface)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOccurrenceTile(Occurance o, Color onSurface) {
    return InkWell(
      onTap: () => _openFileAt(o.line, o.col),
      child: Container(
        padding: const EdgeInsets.fromLTRB(40, 10, 12, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: onSurface.withValues(alpha: 0.03)))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text("LINE ${o.line}",
                    style: TextStyle(
                        fontSize: 9,
                        color: userSettings.themeColors.accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                const SizedBox(width: 8),
                Text("COL ${o.col}",
                    style: TextStyle(
                        fontSize: 9,
                        color: onSurface.withValues(alpha: 0.4),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: onSurface.withValues(alpha: 0.05)),
              ),
              child: Text(
                o.lines.join("\n").trim(),
                style: const TextStyle(fontFamily: "monospace", fontSize: 11, height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTinyIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
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
            color: onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: onSurface.withValues(alpha: 0.08)),
          ),
          child: Icon(icon, size: 16, color: onSurface.withValues(alpha: 0.6)),
        ),
      ),
    );
  }

  void _openFile() {
    if (widget.openInCode) {
      WinUtils.open("code", arguments: '"${widget.filePath}"');
    } else {
      WinUtils.open(widget.filePath);
    }
  }

  void _openFileAt(int line, int col) {
    if (widget.openInCode) {
      WinUtils.open("code", arguments: '--goto "${widget.filePath}:$line:$col"');
    } else {
      WinUtils.open(widget.filePath);
    }
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
  int line;
  int col;
  List<String> lines;
  Occurance({
    required this.line,
    required this.col,
    required this.lines,
  });

  @override
  String toString() {
    return 'Occurance(file: line: $line, col: $col, lines: $lines)';
  }
}
