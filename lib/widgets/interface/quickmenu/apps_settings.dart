import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../itzy/quickmenu/button_window_app.dart';
import '../../widgets/custom_tooltip.dart';
import 'apps_category_editor.dart';

class QuickmenuAppsSettings extends StatefulWidget {
  const QuickmenuAppsSettings({super.key});

  @override
  State<QuickmenuAppsSettings> createState() => _QuickmenuAppsSettingsState();
}

class _QuickmenuAppsSettingsState extends State<QuickmenuAppsSettings> {
  late List<AppCategory> categories;
  final List<AppItem> listOfApps = <AppItem>[];

  final StreamController<List<AppCategory>> _categoriesController = StreamController<List<AppCategory>>.broadcast();
  final StreamController<List<AppItem>> _sourceController = StreamController<List<AppItem>>.broadcast();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchNotifier = ValueNotifier<String>("");
  final ScrollController _sourceScrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();
  bool _isSourceLoading = false;
  String _sourceLoadingLabel = "Loading apps...";

  @override
  void initState() {
    super.initState();
    categories = List<AppCategory>.from(Boxes.appCategories);
    _searchController.addListener(_handleSearchChanged);
    _emitCollections();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _searchNotifier.dispose();
    _sourceScrollController.dispose();
    _categoriesScrollController.dispose();
    _categoriesController.close();
    _sourceController.close();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchNotifier.value = _searchController.text.trim().toLowerCase();
  }

  void _emitCollections() {
    if (!_categoriesController.isClosed) {
      _categoriesController.add(List<AppCategory>.from(categories));
    }
    if (!_sourceController.isClosed) {
      _sourceController.add(List<AppItem>.from(listOfApps));
    }
  }

  void _save() {
    Boxes.appCategories = categories;
    _emitCollections();
  }

  String _displayNameFromPath(String path) {
    final String filename = path.split(RegExp(r'[\\/]')).last;
    return filename.replaceFirst(
      RegExp(r'\.(exe|lnk|url)$', caseSensitive: false),
      "",
    );
  }

  bool _containsPath(List<AppItem> items, String path) {
    return items.any((AppItem item) => item.path == path);
  }

  void _addToListOfApps(Iterable<AppItem> items) {
    for (final AppItem item in items) {
      if (_containsPath(listOfApps, item.path)) continue;
      listOfApps.add(item);
    }
  }

  Future<List<AppItem>> _collectAppsFromDirectories(
    Iterable<String> paths, {
    required Set<String> extensions,
  }) async {
    final Map<String, AppItem> foundApps = <String, AppItem>{};

    for (final String path in paths) {
      final Directory dir = Directory(path);
      if (!await dir.exists()) continue;

      try {
        final Stream<FileSystemEntity> stream = dir.list(recursive: true, followLinks: false).handleError((Object e) {
          // Ignore permission denied or other filesystem errors during recursion
        });

        await for (final FileSystemEntity entity in stream) {
          if (entity is! File) continue;

          final String normalizedPath = entity.path.toLowerCase();
          final bool matchesExtension = extensions.any((String ext) => normalizedPath.endsWith(ext.toLowerCase()));
          if (!matchesExtension) continue;

          foundApps.putIfAbsent(
            entity.path,
            () => AppItem(
              name: _displayNameFromPath(entity.path),
              path: entity.path,
            ),
          );
        }
      } catch (_) {
        // Ignore errors for the top-level directory listing itself
      }
    }

    return foundApps.values.toList(growable: false);
  }

  Future<void> _runSourceLoading(
    String label,
    Future<List<AppItem>> Function() loader,
  ) async {
    if (_isSourceLoading) return;

    setState(() {
      _isSourceLoading = true;
      _sourceLoadingLabel = label;
    });

    try {
      final List<AppItem> items = await loader();
      if (!mounted) return;
      _addToListOfApps(items);
      _save();
    } finally {
      if (mounted) {
        setState(() {
          _isSourceLoading = false;
        });
      }
    }
  }

  Future<void> _scanStartMenu() async {
    final List<String> paths = <String>[
      "${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
      "${Platform.environment['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
    ];

    await _runSourceLoading(
      "Scanning Start Menu...",
      () => _collectAppsFromDirectories(
        paths,
        extensions: <String>{".lnk", ".url"},
      ),
    );
  }

  Future<void> _addFolder() async {
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select apps folder';
    final Directory? dir = dirPicker.getDirectory();
    if (dir == null || dir.path.isEmpty) return;

    await _runSourceLoading(
      "Scanning folder...",
      () => _collectAppsFromDirectories(
        <String>[dir.path],
        extensions: <String>{".exe", ".lnk", ".url"},
      ),
    );
  }

  void _clearList() {
    listOfApps.clear();
    _save();
  }

  void _addCategory() {
    categories.add(AppCategory(name: "New Category"));
    _save();
  }

  void _assignAppToCategory(AppItem app, int categoryIndex) {
    final AppCategory targetCategory = categories[categoryIndex];
    final bool alreadyExists = targetCategory.items.any(
      (AppItem item) => item.path == app.path,
    );
    if (!alreadyExists) {
      targetCategory.items.add(
        AppItem(name: app.name, path: app.path, arguments: app.arguments),
      );
    }
    _save();
  }

  void _onCategoriesReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final AppCategory item = categories.removeAt(oldIndex);
      categories.insert(newIndex, item);
      _save();
    });
  }

  Future<void> _openCategoryEditor(int categoryIndex) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          child: QuickmenuAppsCategoryEditor(
            categoryIndex: categoryIndex,
          ),
        ),
      ),
    );

    categories = List<AppCategory>.from(Boxes.appCategories);
    _emitCollections();
  }

  Future<void> _openAiCategorizeModal() async {
    if (listOfApps.isEmpty) return;

    final TextEditingController aiOutputController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    "AI Categorization",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "1. Copy the prompt below and paste it into any AI model.\n2. Copy the resulting JSON output and paste it here.\n3. Click Import to auto-categorize your apps.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text("Copy Prompt for AI"),
                    onPressed: () {
                      final Map<String, String> appData = <String, String>{};
                      for (int i = 0; i < listOfApps.length; i++) {
                        appData[i.toString()] = listOfApps[i].name;
                      }

                      final String prompt = '''
Please group these apps into categories. 
One VERY important category must be "Others" where you should place apps that no one typically uses manually (like default Windows built-in utilities, background services, or extremely obscure apps).
Other categories worth mentioning should be Games, Productivity Apps, Editors.
Your output MUST be ONLY a valid raw JSON object strictly in this format: 
{"CategoryName": [id_1, id_2], "CategoryName2": [id_3, id_4], "Others": [id_5, id_6]}

Apps data:
${jsonEncode(appData)}
''';
                      Clipboard.setData(ClipboardData(text: prompt));
                    },
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: aiOutputController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: "Paste AI output JSON here...",
                      hintStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(80)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text("CANCEL"),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          try {
                            final Map<String, dynamic> output =
                                jsonDecode(aiOutputController.text) as Map<String, dynamic>;
                            for (final String categoryName in output.keys) {
                              final List<dynamic> ids = output[categoryName] as List<dynamic>;

                              final AppCategory newCategory = AppCategory(name: categoryName);

                              for (final dynamic rowId in ids) {
                                final int? i = int.tryParse(rowId.toString());
                                if (i != null && i >= 0 && i < listOfApps.length) {
                                  final AppItem refApp = listOfApps[i];
                                  final bool alreadyExists =
                                      newCategory.items.any((AppItem item) => item.path == refApp.path);
                                  if (!alreadyExists) {
                                    newCategory.items.add(
                                        AppItem(name: refApp.name, path: refApp.path, arguments: refApp.arguments));
                                  }
                                }
                              }

                              if (newCategory.items.isNotEmpty) {
                                categories.add(newCategory);
                              }
                            }

                            _save();
                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            // Suppress error quietly based on dialog constraint avoiding ScaffoldMessenger, or let it fail gracefully.
                          }
                        },
                        child: const Text("IMPORT"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Staging Deck (Source)
              Expanded(
                flex: 13,
                child: _buildStagingDeck(context),
              ),
              // const SizedBox(width: 5), // Increased separation for better panel distinction
              // Category Buckets (Targets)
              Expanded(
                flex: 7,
                child: _buildCategoryBuckets(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStagingDeck(BuildContext context) {
    return StreamBuilder<List<AppItem>>(
      stream: _sourceController.stream,
      initialData: listOfApps,
      builder: (BuildContext context, AsyncSnapshot<List<AppItem>> snapshot) {
        final List<AppItem> items = snapshot.data ?? listOfApps;

        return _buildPanel(
          context: context,
          title: "STAGING DECK",
          subtitle: "Discovered apps ready for curation",
          actions: <Widget>[
            if (items.isNotEmpty)
              _buildDeckAction(context, "AI CATEGORIZE", Icons.auto_awesome_rounded, _openAiCategorizeModal),
            _buildDeckAction(context, "SCAN START", Icons.refresh_rounded, _scanStartMenu),
            _buildDeckAction(context, "ADD FOLDER", Icons.folder_open_rounded, _addFolder),
            _buildDeckAction(context, "CLEAR", Icons.delete_sweep_rounded, _clearList, isDanger: true),
          ],
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _buildSearchField(context),
              ),
              Expanded(
                child: _isSourceLoading
                    ? _buildSourceLoadingState(context)
                    : ValueListenableBuilder<String>(
                        valueListenable: _searchNotifier,
                        builder: (BuildContext context, String searchQuery, _) {
                          final List<AppItem> filtered =
                              items.where((AppItem app) => app.name.toLowerCase().contains(searchQuery)).toList();

                          if (filtered.isEmpty) {
                            return _buildEmptyState(
                              context,
                              icon: Icons.inventory_2_outlined,
                              title: searchQuery.isEmpty ? "DECK EMPTY" : "NO MATCHES",
                              message: searchQuery.isEmpty
                                  ? "Scan your Start Menu or add folders to populate the deck."
                                  : "Try a broader search term.",
                            );
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              mainAxisExtent: 64,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (BuildContext context, int index) => _buildAppTile(context, filtered[index]),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryBuckets(BuildContext context) {
    return StreamBuilder<List<AppCategory>>(
      stream: _categoriesController.stream,
      initialData: categories,
      builder: (BuildContext context, AsyncSnapshot<List<AppCategory>> snapshot) {
        final List<AppCategory> categoryItems = snapshot.data ?? categories;
        final int totalApps = categoryItems.fold<int>(0, (int total, AppCategory c) => total + c.items.length);

        return _buildPanel(
          context: context,
          title: "TARGET BUCKETS",
          subtitle: "${categoryItems.length} categories • $totalApps apps",
          isLandingZone: true,
          actions: <Widget>[
            _buildDeckAction(context, "NEW BUCKET", Icons.add_rounded, _addCategory),
          ],
          child: categoryItems.isEmpty
              ? _buildEmptyState(
                  context,
                  icon: Icons.dashboard_customize_outlined,
                  title: "NO TARGETS",
                  message: "Create your first category bucket here, then drag apps from the deck.",
                )
              : ReorderableListView.builder(
                  onReorder: _onCategoriesReorder,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  itemCount: categoryItems.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _buildDropZoneTile(context, categoryItems[index], index),
                ),
        );
      },
    );
  }

  Widget _buildPanel({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<Widget> actions,
    required Widget child,
    bool isLandingZone = false,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: isLandingZone ? onSurface.withValues(alpha: 0.04) : onSurface.withValues(alpha: 0.02),
        borderRadius: isLandingZone
            ? const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24))
            : const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
        border: isLandingZone
            ? Border(
                top: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.15), width: 1.5),
                right: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.15), width: 1.5),
                bottom: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.15), width: 1.5),
              )
            : Border.all(
                color: onSurface.withValues(alpha: 0.08),
                width: 1.5,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18), // Gracious header spacing
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing:
                        0, // Using 0 because actions have their own subtle margin/alignment if needed, but best to control here
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: onSurface.withValues(alpha: 0.08)),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildDeckAction(BuildContext context, String label, IconData icon, VoidCallback? onPressed,
      {bool isDanger = false}) {
    final ThemeData theme = Theme.of(context);
    final Color color = isDanger ? theme.colorScheme.error : theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _searchNotifier,
      builder: (BuildContext context, String searchQuery, _) {
        return TextField(
          controller: _searchController,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: _compactInputDecoration(
            context,
            hintText: "Search apps",
            prefixIcon: const Icon(Icons.search, size: 16),
            suffixIcon: searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: "Clear",
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _searchController.clear,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAppTile(BuildContext context, AppItem app) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Draggable<AppItem>(
      data: app,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(color: primary.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(width: 24, height: 24, child: WindowsAppButton(path: app.path)),
              const SizedBox(width: 10),
              Text(
                app.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      child: _AppTileContent(app: app),
    );
  }

  Widget _buildDropZoneTile(BuildContext context, AppCategory category, int index) {
    return DragTarget<AppItem>(
      key: ValueKey<AppCategory>(category),
      onWillAcceptWithDetails: (DragTargetDetails<AppItem> details) =>
          !category.items.any((AppItem i) => i.path == details.data.path),
      onAcceptWithDetails: (DragTargetDetails<AppItem> details) => _assignAppToCategory(details.data, index),
      builder: (BuildContext context, List<AppItem?> candidateData, List<dynamic> rejectedData) {
        final bool isHovered = candidateData.isNotEmpty;
        return _BucketTile(
          category: category,
          index: index,
          isDropTarget: isHovered,
          onTap: () => _openCategoryEditor(index),
        );
      },
    );
  }

  InputDecoration _compactInputDecoration(
    BuildContext context, {
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.3)),
      prefixIcon:
          prefixIcon != null ? Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: prefixIcon) : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      filled: true,
      fillColor: onSurface.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.08), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.08), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4), width: 1.5),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceLoadingState(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _sourceLoadingLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              controller: _sourceScrollController,
              primary: false,
              itemCount: 6,
              itemBuilder: (BuildContext context, int index) {
                return _buildSourceSkeletonTile(context, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSkeletonTile(BuildContext context, int index) {
    final ThemeData theme = Theme.of(context);
    final double opacity = 0.16 + ((index % 3) * 0.04);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          _buildSkeletonBlock(
            context,
            width: 34,
            height: 34,
            radius: 10,
            opacity: opacity,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildSkeletonBlock(
                  context,
                  width: double.infinity,
                  height: 12,
                  radius: 6,
                  opacity: opacity + 0.05,
                ),
                const SizedBox(height: 8),
                _buildSkeletonBlock(
                  context,
                  width: 180,
                  height: 10,
                  radius: 6,
                  opacity: opacity,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildSkeletonBlock(
            context,
            width: 92,
            height: 30,
            radius: 10,
            opacity: opacity,
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBlock(
    BuildContext context, {
    required double width,
    required double height,
    required double radius,
    required double opacity,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _AppTileContent extends StatefulWidget {
  const _AppTileContent({required this.app});
  final AppItem app;

  @override
  State<_AppTileContent> createState() => _AppTileContentState();
}

class _AppTileContentState extends State<_AppTileContent> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.grab,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isHovered
                ? <Color>[
                    primary.withValues(alpha: 0.08),
                    primary.withValues(alpha: 0.15),
                    primary.withValues(alpha: 0.20),
                    primary.withValues(alpha: 0.20)
                  ]
                : <Color>[onSurface.withValues(alpha: 0.03), onSurface.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered ? primary.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                height: 32,
                child: RepaintBoundary(child: WindowsAppButton(path: widget.app.path)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _isHovered ? primary : onSurface,
                      ),
                    ),
                    if (_isHovered)
                      Text(
                        widget.app.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 8, color: onSurface.withValues(alpha: 0.4)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BucketTile extends StatefulWidget {
  const _BucketTile({
    required this.category,
    required this.index,
    required this.isDropTarget,
    required this.onTap,
  });

  final AppCategory category;
  final int index;
  final bool isDropTarget;
  final VoidCallback onTap;

  @override
  State<_BucketTile> createState() => _BucketTileState();
}

class _BucketTileState extends State<_BucketTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    final bool isFolderSync = widget.category.folderPath != null && widget.category.folderPath!.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDropTarget
                ? <Color>[primary.withValues(alpha: 0.15), primary.withValues(alpha: 0.3)]
                : (_isHovered
                    ? <Color>[
                        primary.withValues(alpha: 0.08),
                        primary.withValues(alpha: 0.15),
                        primary.withValues(alpha: 0.20),
                        primary.withValues(alpha: 0.20)
                      ]
                    : <Color>[onSurface.withValues(alpha: 0.03), onSurface.withValues(alpha: 0.08)]),
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                (widget.isDropTarget || _isHovered) ? primary.withValues(alpha: 0.4) : onSurface.withValues(alpha: 0.1),
            width: 1.5,
          ),
          boxShadow: <BoxShadow>[
            if (widget.isDropTarget) BoxShadow(color: primary.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 2)
          ],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: ReorderableDragStartListener(
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.category.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: (widget.isDropTarget || _isHovered) ? primary : onSurface,
                          ),
                        ),
                        Text(
                          "${widget.category.items.length} items • ${widget.category.viewType.name.toUpperCase()}",
                          style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.4)),
                        ),
                      ],
                    ),
                  ),
                  if (isFolderSync)
                    CustomTooltip(
                      message: "Synced to: ${widget.category.folderPath}",
                      child: Icon(Icons.link_rounded, size: 14, color: primary.withValues(alpha: 0.6)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
