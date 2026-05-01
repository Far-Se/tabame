// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/util/task_runner.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/popup_dialog.dart';

class ProjectOverviewWidget extends StatefulWidget {
  const ProjectOverviewWidget({super.key});

  @override
  ProjectOverviewWidgetState createState() => ProjectOverviewWidgetState();
}

class Project {
  List<ProjectFile> projectFiles = <ProjectFile>[];
  int totalComments = 0;
  int totalLines = 0;
  int totalCode = 0;
  int totalEmpty = 0;
  int totalNonCode = 0;
  int totalChars = 0;
  List<List<String>> _languageList = <List<String>>[];

  void reset() {
    projectFiles = <ProjectFile>[];
    totalComments = 0;
    totalLines = 0;
    totalCode = 0;
    totalEmpty = 0;
    totalNonCode = 0;
    totalChars = 0;
    _languageList = <List<String>>[];
  }

  List<List<String>> get programmingLanguages {
    if (_languageList.isNotEmpty) return _languageList;
    final Map<String, int> exts = <String, int>{};
    for (final ProjectFile file in projectFiles) {
      exts[file.ext] = (exts[file.ext] ?? 0) + file.total.lines;
    }
    final List<MapEntry<String, int>> extsList = exts.entries.toList();
    extsList.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    _languageList = extsList.map((MapEntry<String, int> entry) => <String>[entry.key, entry.value.toString()]).toList();
    return _languageList;
  }

  // Dashboard Metrics
  double get commentDensity => totalLines > 0 ? (totalComments / totalLines) * 100 : 0;
  double get codeIntensity => totalLines > 0 ? totalChars / totalLines : 0;
  double get avgLinesPerFile => projectFiles.isNotEmpty ? totalLines / projectFiles.length : 0;
}

class ProjectOverviewWidgetState extends State<ProjectOverviewWidget> {
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();
  final TextEditingController _gitLinkController = TextEditingController();

  bool showFilters = false;
  bool showGit = false;
  bool projectAnalyzed = false;
  bool projectUseGitIgnore = true;
  int stateFileProcessing = 0; // 0: idle, 1: processing, 2: cancel
  int totalFilesToProcess = 0;
  int processedFilesCount = 0;
  String infoText = "";

  Map<String, Color> extColors = <String, Color>{};
  final List<int> extensionColors = <int>[
    0xff34B7FD,
    0xffCB4802,
    0xffFFA700,
    0xffC3732A,
    0xffA4DDED,
    0xff922724,
    0xff43B3AE,
    0xffA020F0
  ];

  Project project = Project();
  List<String> loadedFiles = <String>[];

  // Sorting
  int sortColumnIndex = 1;
  bool sortAscending = false;

  @override
  void initState() {
    super.initState();
    _folderController.text = Boxes.pref.getString("projectOverviewFolder") ?? "";
    _includeController.text = Boxes.pref.getString("projectOverviewIncluded") ?? "";
    _excludeController.text =
        Boxes.pref.getString("projectOverviewExcluded") ?? r"^\.[a-z];node_modules;(json|ml)$;\w{4,}$";

    if (globalSettings.args.contains("-wizardly")) {
      _folderController.text = globalSettings.args[0].replaceAll('"', '');
    }
  }

  @override
  void dispose() {
    _folderController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    _gitLinkController.dispose();
    super.dispose();
  }

  Widget _buildLoadingOverlay(Color accent, Color onSurface) {
    if (stateFileProcessing != 1) return const SizedBox.shrink();

    final double progress = totalFilesToProcess > 0 ? processedFilesCount / totalFilesToProcess : 0.0;

    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: totalFilesToProcess > 0 ? progress : null,
                      strokeWidth: 6,
                      backgroundColor: accent.withValues(alpha: 0.1),
                    ),
                  ),
                  Text("${(progress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              const Text("Analyzing Project", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                totalFilesToProcess > 0
                    ? "Processing: $processedFilesCount / $totalFilesToProcess files"
                    : "Scanning directory...",
                style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => setState(() => stateFileProcessing = 2),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text("Cancel Analysis"),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color background = globalSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Stack(
      children: <Widget>[
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(accent, background, onSurface),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: Column(
                children: <Widget>[
                  if (showGit) _buildGitSection(accent, onSurface),
                  if (showFilters) _buildFilterBar(accent, onSurface),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildResultsView(accent, onSurface),
            ),
          ],
        ),
        _buildLoadingOverlay(accent, onSurface),
      ],
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.all(12),
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
                    Icon(Icons.folder_open_rounded, color: accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text("Target Folder", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            _folderController.text.isEmpty
                                ? "No folder selected"
                                : _folderController.text.truncate(60, suffix: "..."),
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
          const SizedBox(width: 8),
          _buildIconButton(
            icon: Icons.settings_rounded,
            isSelected: showFilters,
            onPressed: () => setState(() => showFilters = !showFilters),
            tooltip: "Filters & Options",
            onSurface: onSurface,
          ),
          _buildIconButton(
            icon: Icons.cloud_download_rounded,
            isSelected: showGit,
            onPressed: () => setState(() => showGit = !showGit),
            tooltip: "Load from Git",
            onSurface: onSurface,
          ),
          const SizedBox(width: 8),
          _buildActionButton(accent, background),
        ],
      ),
    );
  }

  Widget _buildIconButton(
      {required IconData icon,
      required bool isSelected,
      required VoidCallback onPressed,
      required String tooltip,
      required Color onSurface}) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor:
            isSelected ? globalSettings.themeColors.accentColor.withValues(alpha: 0.1) : Colors.transparent,
        foregroundColor: isSelected ? globalSettings.themeColors.accentColor : onSurface.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildActionButton(Color accent, Color background) {
    final bool isProcessing = stateFileProcessing == 1;
    return ElevatedButton.icon(
      icon: isProcessing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.analytics_rounded, color: background),
      label: Text(isProcessing ? "Stop" : "Analyze", style: TextStyle(color: background, fontWeight: FontWeight.bold)),
      onPressed: _onAnalyzePressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isProcessing ? Colors.redAccent : accent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildFilterBar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onSurface.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _buildFilterInput("Include Extensions", _includeController, "dart;js;css", onSurface)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildFilterInput("Exclude Patterns", _excludeController, "node_modules;build", onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 200,
                  child: CheckBoxWidget(
                    value: projectUseGitIgnore,
                    onChanged: (bool e) => setState(() => projectUseGitIgnore = e),
                    text: 'Respect .gitignore',
                  ),
                ),
                const Spacer(),
                Text(infoText, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterInput(String label, TextEditingController controller, String hint, Color onSurface) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        floatingLabelStyle: TextStyle(color: globalSettings.themeColors.accentColor),
      ),
    );
  }

  Widget _buildGitSection(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: LoadFromGitWidget(
          onSelected: (String folder) {
            _folderController.text = folder;
            setState(() => showGit = false);
            _onAnalyzePressed();
          },
        ),
      ),
    );
  }

  Widget _buildResultsView(Color accent, Color onSurface) {
    if (!projectAnalyzed && stateFileProcessing == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.insert_chart_outlined_rounded, size: 64, color: onSurface.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text("Select a folder to analyze your project", style: TextStyle(color: onSurface.withValues(alpha: 0.4))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildStatsDashboard(accent, onSurface),
        const SizedBox(height: 24),
        _buildVisualSection(accent, onSurface),
        const SizedBox(height: 24),
        _buildFilesSection(accent, onSurface),
      ],
    );
  }

  Widget _buildStatsDashboard(Color accent, Color onSurface) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: <Widget>[
        _buildMetricCard("Lines of Code", project.totalLines.decimal, Icons.reorder_rounded, accent, onSurface),
        _buildMetricCard("Comment Density", "${project.commentDensity.toStringAsFixed(1)}%", Icons.comment_bank_rounded,
            Colors.green, onSurface),
        _buildMetricCard("Code Intensity", "${project.codeIntensity.toStringAsFixed(1)} ch/ln", Icons.bolt_outlined,
            Colors.orange, onSurface),
        _buildMetricCard("Avg. File Length", "${project.avgLinesPerFile.floor().decimal} lns",
            Icons.file_present_rounded, Colors.blue, onSurface),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5), height: 1.1),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualSection(Color accent, Color onSurface) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 40,
                sections: List<PieChartSectionData>.generate(project.programmingLanguages.length, (int index) {
                  final String lang = project.programmingLanguages[index][0];
                  final double percentage =
                      (int.parse(project.programmingLanguages[index][1]) / project.totalLines) * 100;
                  return PieChartSectionData(
                    title: percentage > 10 ? "$lang\n${percentage.toStringAsFixed(0)}%" : "",
                    value: percentage,
                    color: extColors[lang] ?? Colors.grey,
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }),
              ),
            ),
          ),
          const VerticalDivider(width: 40),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: project.programmingLanguages.map((List<String> langData) {
                final String lang = langData[0];
                final int lines = int.parse(langData[1]);
                return _buildLanguageChip(lang, lines, extColors[lang] ?? Colors.grey, onSurface);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip(String lang, int lines, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(lang, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 6),
          Text(lines.decimal, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildFilesSection(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text("File Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text("${project.projectFiles.length} files tracked",
                style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 12),
        _buildFileTableHeader(onSurface),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: project.projectFiles.length,
          itemBuilder: (BuildContext context, int index) {
            final ProjectFile file = project.projectFiles[index];
            return _buildFileRow(file, index, accent, onSurface);
          },
        ),
      ],
    );
  }

  Widget _buildFileTableHeader(Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
              flex: 4, child: Text("File Path", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          _buildSortableHeader("Lines", 1, 70, onSurface),
          _buildSortableHeader("Code", 2, 70, onSurface),
          _buildSortableHeader("Comments", 3, 70, onSurface),
          _buildSortableHeader("Empty", 4, 70, onSurface),
          _buildSortableHeader("Chars", 5, 80, onSurface),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(String label, int index, double width, Color onSurface) {
    final bool isSelected = sortColumnIndex == index;
    return InkWell(
      onTap: () => _sortFiles(index),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSelected ? globalSettings.themeColors.accentColor : onSurface.withValues(alpha: 0.5))),
            if (isSelected)
              Icon(sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 16, color: globalSettings.themeColors.accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(ProjectFile file, int index, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: onSurface.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Row(
              children: <Widget>[
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: extColors[file.ext] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(file.path, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          _buildColText(file.total.lines.decimal, 70, onSurface),
          _buildColText(file.total.code.decimal, 70, onSurface),
          _buildColText(file.total.comments.decimal, 70, onSurface, color: Colors.green),
          _buildColText(file.total.empty.decimal, 70, onSurface, opacity: 0.4),
          _buildColText(file.total.characters.decimal, 80, onSurface),
        ],
      ),
    );
  }

  Widget _buildColText(String text, double width, Color onSurface, {Color? color, double opacity = 1.0}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: (color ?? onSurface).withValues(alpha: opacity)),
      ),
    );
  }

  void _onAnalyzePressed() async {
    if (stateFileProcessing == 1) {
      stateFileProcessing = 2; // Signal cancel
      return;
    }

    final String folder = _folderController.text;
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      popupDialog(context, "Please select a valid folder");
      return;
    }

    project.reset();
    loadedFiles.clear();
    projectAnalyzed = false;
    infoText = "Scanning directory...";
    stateFileProcessing = 1;
    if (mounted) setState(() {});

    await loadFiles();
    if (stateFileProcessing == 2) {
      stateFileProcessing = 0;
      if (mounted) setState(() {});
      return;
    }

    getCode();
  }

  void _pickFolder() async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select project folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null) return;
    _folderController.text = dir.path;
    Boxes.updateSettings("projectOverviewFolder", dir.path);
    if (mounted) setState(() {});
  }

  void _sortFiles(int columnIndex) {
    setState(() {
      if (sortColumnIndex == columnIndex) {
        sortAscending = !sortAscending;
      } else {
        sortColumnIndex = columnIndex;
        sortAscending = false;
      }

      project.projectFiles.sort((ProjectFile a, ProjectFile b) {
        dynamic valA, valB;
        switch (columnIndex) {
          case 1:
            valA = a.total.lines;
            valB = b.total.lines;
            break;
          case 2:
            valA = a.total.code;
            valB = b.total.code;
            break;
          case 3:
            valA = a.total.comments;
            valB = b.total.comments;
            break;
          case 4:
            valA = a.total.empty;
            valB = b.total.empty;
            break;
          case 5:
            valA = a.total.characters;
            valB = b.total.characters;
            break;
          default:
            valA = a.total.lines;
            valB = b.total.lines;
        }
        return sortAscending ? valA.compareTo(valB) : valB.compareTo(valA);
      });
    });
  }

  Future<void> getCode() async {
    project.reset();
    final String projectFolder = _folderController.text;
    final List<String> auxFiles = <String>[...loadedFiles];

    Future<bool> getFileInfo(String file) async {
      try {
        final List<String> fileLines = await File(file).readAsLines().catchError((_) => <String>[]);
        if (fileLines.isEmpty) {
          loadedFiles.remove(file);
          return true;
        }

        final String relativePath = file.replaceFirst("$projectFolder\\", "");
        final String fileName = relativePath.split(r'\').last;
        final String fileExtension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : "txt";

        final TotalCode total = TotalCode();
        total.lines = fileLines.length;

        bool inMultiComment = false;
        String multiStart = "/*";
        String multiEnd = "*/";
        String singleComment = "//";

        if (multiLineComment.containsKey(fileExtension)) {
          multiStart = multiLineComment[fileExtension]!.multiCommentStart;
          multiEnd = multiLineComment[fileExtension]!.multiCommentEnd;
        }

        if (const <String>["py", "ps1", "rb", "r", "yaml", "yml", "toml"].contains(fileExtension)) {
          singleComment = "#";
        }

        int lineCounter = 0;
        for (String line in fileLines) {
          final String trimmed = line.trim();
          total.characters += trimmed.length;

          if (inMultiComment) {
            total.comments++;
            if (trimmed.contains(multiEnd)) inMultiComment = false;
          } else if (trimmed.startsWith(multiStart)) {
            total.comments++;
            if (!trimmed.contains(multiEnd)) inMultiComment = true;
          } else if (trimmed.startsWith(singleComment)) {
            total.comments++;
          } else if (trimmed.isEmpty) {
            total.empty++;
          } else if (!RegExp(r'\w').hasMatch(trimmed)) {
            total.nonCode++;
          } else {
            total.code++;
          }

          // Yield every 2000 lines of processing to keep UI responsive
          lineCounter++;
          if (lineCounter % 2000 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }

        // Adjust for any uncategorized lines
        int categorized = total.code + total.comments + total.nonCode + total.empty;
        if (categorized < total.lines) {
          total.empty += (total.lines - categorized);
        }

        project.projectFiles.add(ProjectFile(name: fileName, path: relativePath, ext: fileExtension, total: total));
        return true;
      } catch (e) {
        return true;
      }
    }

    final TaskRunner<String, bool> runner =
        TaskRunner<String, bool>(getFileInfo, maxConcurrentTasks: 10); // Lower concurrency to prioritize UI
    for (String file in auxFiles) {
      if (stateFileProcessing == 2) break;
      runner.add(file);
    }

    runner.startExecution();

    runner.stream.listen((_) {
      if (mounted) {
        setState(() {
          processedFilesCount++;
        });
      }
      if (stateFileProcessing == 2 || processedFilesCount >= auxFiles.length) {
        _finalizeAnalysis();
      }
    });

    // If no files to process, finalize immediately
    if (auxFiles.isEmpty) _finalizeAnalysis();
  }

  void _finalizeAnalysis() {
    stateFileProcessing = 0;
    projectAnalyzed = true;

    // Sorting by lines descending initially
    project.projectFiles.sort((ProjectFile a, ProjectFile b) => b.total.lines.compareTo(a.total.lines));

    // Aggregate totals
    for (ProjectFile file in project.projectFiles) {
      project.totalComments += file.total.comments;
      project.totalLines += file.total.lines;
      project.totalCode += file.total.code;
      project.totalEmpty += file.total.empty;
      project.totalNonCode += file.total.nonCode;
      project.totalChars += file.total.characters;
    }

    // Initialize colors
    int colorIdx = 0;
    for (List<String> lang in project.programmingLanguages) {
      if (colorIdx >= extensionColors.length) break;
      extColors[lang[0]] = Color(extensionColors[colorIdx++]);
    }

    infoText = "Analysis complete: ${project.totalLines.decimal} lines in ${project.projectFiles.length} files";
    if (mounted) setState(() {});
  }

  Future<void> loadFiles() async {
    final String projectFolder = _folderController.text;
    final File gitignoreFile = File("$projectFolder\\.gitignore");
    final List<String> gitIgnorePatterns = <String>[];

    if (gitignoreFile.existsSync() && projectUseGitIgnore) {
      final List<String> lines = await gitignoreFile.readAsLines();
      for (String line in lines) {
        final String clean = line.trim();
        if (clean.isEmpty || clean.startsWith('#')) continue;

        String pattern = clean.replaceAll(RegExp(r'#.*?$'), '').trim();
        pattern = pattern.replaceAll('.', r'\.').replaceAll('*', '.*').replaceAll('/', r'\\');
        try {
          RegExp(pattern); // Validate
          gitIgnorePatterns.add(pattern);
        } catch (_) {}
      }
    }

    final List<String> allFiles = <String>[];
    int counter = 0;
    try {
      final Stream<FileSystemEntity> stream = Directory(projectFolder).list(recursive: true, followLinks: false);
      await for (FileSystemEntity entity in stream) {
        if (entity is! File) continue;

        bool isIgnored = false;
        for (String pattern in gitIgnorePatterns) {
          if (RegExp(pattern, caseSensitive: false).hasMatch(entity.path)) {
            isIgnored = true;
            break;
          }
        }
        if (!isIgnored) allFiles.add(entity.path);

        // Yield to event loop every 500 files to keep UI alive
        counter++;
        if (counter % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }

        if (stateFileProcessing == 2) return;
      }
    } catch (e) {
      // infoText = "Error scanning directory: $e";
    }

    final List<String> included =
        _includeController.text.split(';').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
    final List<String> excluded =
        _excludeController.text.split(';').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();

    loadedFiles.clear();
    for (String file in allFiles) {
      if (stateFileProcessing == 2) return;
      final String fileName = file.split(r'\').last;

      final String lowerName = fileName.toLowerCase();
      if (const <String>["svg", "lock", "png", "jpg", "jpeg", "gif", "ico", "exe", "dll", "bin"]
          .any((String ext) => lowerName.endsWith(".$ext"))) {
        continue;
      }
      if (!fileName.contains('.')) {
        continue;
      }

      bool skip = false;
      for (String exclude in excluded) {
        if (RegExp(exclude, caseSensitive: false).hasMatch(file)) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      if (included.isNotEmpty) {
        bool isIncluded = false;
        for (String include in included) {
          if (lowerName.endsWith(include.toLowerCase())) {
            isIncluded = true;
            break;
          }
        }
        if (!isIncluded) continue;
      }

      loadedFiles.add(file);
    }

    setState(() {
      totalFilesToProcess = loadedFiles.length;
      processedFilesCount = 0;
    });
  }
}

extension DecimalFormat on int {
  String get decimal => NumberFormat.decimalPattern().format(this);
}

class TotalCode {
  int lines = 0;
  int comments = 0;
  int code = 0;
  int empty = 0;
  int nonCode = 0;
  int characters = 0;
  @override
  String toString() {
    return 'TotalCode(lines: $lines, comments: $comments, code: $code, empty: $empty, nonCode: $nonCode, characters: $characters)';
  }
}

class ProjectFile {
  String path;
  String name;
  String ext;
  TotalCode total;
  ProjectFile({
    required this.path,
    required this.name,
    required this.ext,
    required this.total,
  });

  @override
  String toString() => 'ProjectFile(path: $path, name: $name, total: $total)';
}

class MultiLineComment {
  String multiCommentStart;
  String multiCommentEnd;
  MultiLineComment(this.multiCommentStart, this.multiCommentEnd);
}

Map<String, MultiLineComment> multiLineComment = <String, MultiLineComment>{
  "htm": MultiLineComment("<!--", "-->"),
  "html": MultiLineComment("<!--", "-->"),
  "ruby": MultiLineComment("=begin", "=end"),
  "ps1": MultiLineComment("<#", "#>"),
  "hs": MultiLineComment("{-", "-}"),
  "lhs": MultiLineComment("{-", "-}"),
  "pas": MultiLineComment("(*", "*)"),
  "cpp": MultiLineComment("/*", "*/"),
  "dart": MultiLineComment("/*", "*/"),
  "js": MultiLineComment("/*", "*/"),
  "css": MultiLineComment("/*", "*/"),
  "java": MultiLineComment("/*", "*/"),
  "go": MultiLineComment("/*", "*/"),
  "rs": MultiLineComment("/*", "*/"),
};

class LoadFromGitWidget extends StatefulWidget {
  final void Function(String folder) onSelected;
  const LoadFromGitWidget({super.key, required this.onSelected});
  @override
  LoadFromGitWidgetState createState() => LoadFromGitWidgetState();
}

class LoadFromGitWidgetState extends State<LoadFromGitWidget> {
  final String baseDir = "${WinUtils.getTabameAppDataFolder()}\\projectOverview";
  String downloadMessage = "Download Project";
  bool isDownloading = false;
  String headerMsg = "Fetch repository content from GitHub or GitLab";
  final List<String> allDirs = <String>[];
  final TextEditingController _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocalSaves();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  void _loadLocalSaves() {
    if (!Directory(baseDir).existsSync()) Directory(baseDir).createSync(recursive: true);
    final List<FileSystemEntity> dirs = Directory(baseDir).listSync(followLinks: false);
    allDirs.clear();
    for (FileSystemEntity x in dirs) {
      if (x is Directory) allDirs.add(x.path);
    }
    if (mounted) setState(() {});
  }

  void _startDownload() async {
    final String link = _linkController.text.trim();
    if (link.isEmpty) return;

    setState(() {
      isDownloading = true;
      downloadMessage = "Connecting...";
    });

    String repoUrl = "";
    if (link.contains("github.com")) {
      final RegExpMatch? reg = RegExp(r'github\.com/(.*?/.*?)(?:\.git|/|$)', caseSensitive: false).firstMatch(link);
      if (reg != null) repoUrl = "https://github.com/${reg[1]!}/archive/refs/heads/master.zip";
    } else if (link.contains("gitlab.com")) {
      final RegExpMatch? reg = RegExp(r'gitlab\.com/(.*?/.*?)(?:\.git|/|$)', caseSensitive: false).firstMatch(link);
      if (reg != null) {
        final String repName = reg[1]!.split('/').last;
        repoUrl = "https://gitlab.com/${reg[1]!}/-/archive/master/$repName.zip";
      }
    }

    if (repoUrl.isEmpty) {
      setState(() {
        isDownloading = false;
        headerMsg = "Invalid or unsupported repository link";
      });
      return;
    }

    final String zipFile = "$baseDir\\temp_archive.zip";
    try {
      await _downloadFile(repoUrl, zipFile, () async {
        setState(() => downloadMessage = "Extracting...");
        WinUtils.open("powershell.exe",
            arguments:
                '-Command "Expand-Archive -LiteralPath \'$zipFile\' -DestinationPath \'$baseDir\' -Force; Remove-Item \'$zipFile\'"');
        await Future<void>.delayed(const Duration(seconds: 2));
        _loadLocalSaves();
        setState(() {
          isDownloading = false;
          downloadMessage = "Download Project";
        });
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
        headerMsg = "Download failed: $e";
      });
    }
  }

  Future<void> _downloadFile(String url, String filename, VoidCallback onDone) async {
    final http.Client client = http.Client();
    final http.Request request = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse response = await client.send(request);

    final List<int> bytes = <int>[];
    int total = 0;
    response.stream.listen(
      (List<int> chunk) {
        bytes.addAll(chunk);
        total += chunk.length;
        if (mounted) {
          setState(() => downloadMessage = "Downloading: ${(total / 1024 / 1024).toStringAsFixed(1)} MB");
        }
      },
      onDone: () async {
        await File(filename).writeAsBytes(bytes);
        onDone();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(headerMsg, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _linkController,
                decoration: InputDecoration(
                  hintText: "GitHub or GitLab repository link",
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: isDownloading ? null : _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(downloadMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (allDirs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Text("Locally Saved Projects", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allDirs.length,
              itemBuilder: (BuildContext context, int index) {
                final String path = allDirs[index];
                final String name = path.split(r'\').last;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.folder_zip_rounded, size: 16),
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    onPressed: () => widget.onSelected(path),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
