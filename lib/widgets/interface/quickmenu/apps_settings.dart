import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../itzy/quickmenu/button_window_app.dart';
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
    final String filename = path.split('\\').last;
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
      final bool existsInCategory = categories.any(
        (AppCategory category) => _containsPath(category.items, item.path),
      );
      if (!existsInCategory) {
        listOfApps.add(item);
      }
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
        await for (final FileSystemEntity entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;

          final String normalizedPath = entity.path.toLowerCase();
          final bool matchesExtension = extensions.any(normalizedPath.endsWith);
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
        // Ignore access errors for some folders.
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

  Future<void> _openCategoryEditor(int categoryIndex) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: QuickmenuAppsCategoryEditor(
          categoryIndex: categoryIndex,
        ),
      ),
    );

    categories = List<AppCategory>.from(Boxes.appCategories);
    _emitCollections();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0 ? constraints.maxHeight : MediaQuery.sizeOf(context).height - 180;

        return ListTileTheme(
          data: Theme.of(context).listTileTheme.copyWith(
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
          child: SizedBox(
            height: availableHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 7, child: _buildSourceSection(context)),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: _buildCategoriesSection(context)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceSection(BuildContext context) {
    return StreamBuilder<List<AppItem>>(
      stream: _sourceController.stream,
      initialData: listOfApps,
      builder: (BuildContext context, AsyncSnapshot<List<AppItem>> snapshot) {
        final List<AppItem> items = snapshot.data ?? listOfApps;

        return _buildSection(
          context: context,
          title: "Source",
          subtitle: categories.isEmpty ? "Create a category first" : "Select a destination from Add in",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: _buildSearchField(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _isSourceLoading ? null : _scanStartMenu,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text("Scan Start Menu"),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: _isSourceLoading ? null : _addFolder,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text("Add Folder"),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: listOfApps.isEmpty || _isSourceLoading ? null : _clearList,
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text("Clear"),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isSourceLoading
                    ? _buildSourceLoadingState(context)
                    : ValueListenableBuilder<String>(
                        valueListenable: _searchNotifier,
                        builder: (BuildContext context, String searchQuery, _) {
                          final List<AppItem> filtered = items
                              .where(
                                (AppItem app) => app.name.toLowerCase().contains(searchQuery),
                              )
                              .toList();

                          if (filtered.isEmpty) {
                            return _buildEmptyState(
                              context,
                              icon: Icons.inventory_2_outlined,
                              title: searchQuery.isEmpty ? "No source apps yet" : "No matching apps",
                              message: searchQuery.isEmpty ? "Scan the Start Menu or add files manually." : "Try a different search term.",
                            );
                          }

                          return Scrollbar(
                            controller: _sourceScrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _sourceScrollController,
                              primary: false,
                              padding: const EdgeInsets.fromLTRB(8, 2, 8, 18),
                              itemCount: filtered.length,
                              itemBuilder: (BuildContext context, int index) {
                                return _buildSourceTile(context, filtered[index]);
                              },
                            ),
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

  Widget _buildCategoriesSection(BuildContext context) {
    return StreamBuilder<List<AppCategory>>(
      stream: _categoriesController.stream,
      initialData: categories,
      builder: (BuildContext context, AsyncSnapshot<List<AppCategory>> snapshot) {
        final List<AppCategory> categoryItems = snapshot.data ?? categories;
        final int totalApps = categoryItems.fold<int>(
          0,
          (int total, AppCategory category) => total + category.items.length,
        );

        return _buildSection(
          context: context,
          title: "Categories",
          subtitle: "${categoryItems.length} groups - $totalApps apps",
          trailing: IconButton(
            onPressed: _addCategory,
            icon: const Icon(Icons.add_rounded, size: 20),
            tooltip: "Add Category",
          ),
          child: categoryItems.isEmpty
              ? _buildEmptyState(
                  context,
                  icon: Icons.dashboard_customize_outlined,
                  title: "No categories yet",
                  message: "Create one on the right, then start placing apps from Source.",
                )
              : Scrollbar(
                  controller: _categoriesScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _categoriesScrollController,
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 18),
                    itemCount: categoryItems.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _buildCategoryTile(
                        context,
                        categoryItems[index],
                        index,
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(child: child),
        ],
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

  Widget _buildSourceTile(BuildContext context, AppItem app) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        minVerticalPadding: 7,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: RepaintBoundary(child: WindowsAppButton(path: app.path)),
        title: Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          app.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.78),
          ),
        ),
        trailing: _buildAddInButton(context, app),
      ),
    );
  }

  Widget _buildAddInButton(BuildContext context, AppItem app) {
    final ThemeData theme = Theme.of(context);

    return PopupMenuButton<int>(
      enabled: categories.isNotEmpty,
      tooltip: categories.isEmpty ? "Create a category first" : "Add to category",
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      elevation: 10,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      onSelected: (int categoryIndex) => _assignAppToCategory(app, categoryIndex),
      itemBuilder: (BuildContext context) {
        return List<PopupMenuEntry<int>>.generate(
          categories.length,
          (int index) => PopupMenuItem<int>(
            value: index,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.folder_open_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categories[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: categories.isEmpty
              ? theme.colorScheme.surface.withValues(alpha: 0.22)
              : theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: categories.isEmpty
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.2)
                : theme.colorScheme.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              categories.isEmpty ? Icons.lock_outline_rounded : Icons.add_rounded,
              size: 14,
              color: categories.isEmpty ? theme.disabledColor : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              categories.isEmpty ? "No category" : "Add to",
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: categories.isEmpty ? theme.disabledColor : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: categories.isEmpty ? theme.disabledColor : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    AppCategory category,
    int index,
  ) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = category.folderPath == null || category.folderPath!.isEmpty
        ? "${category.items.length} apps - ${category.viewType == AppCategoryViewType.grid ? "Grid" : "List"}"
        : "${category.items.length} apps - ${category.folderPath!}";

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        minVerticalPadding: 7,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Icon(
          category.viewType == AppCategoryViewType.grid ? Icons.grid_view_rounded : Icons.view_agenda_rounded,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        onTap: () => _openCategoryEditor(index),
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

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.55, end: 1),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeInOut,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: 0.55 + (value * 0.3),
          child: child,
        );
      },
      onEnd: () {
        if (mounted && _isSourceLoading) {
          setState(() {});
        }
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  InputDecoration _compactInputDecoration(
    BuildContext context, {
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final ThemeData theme = Theme.of(context);
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surface.withValues(alpha: 0.34),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        borderSide: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
