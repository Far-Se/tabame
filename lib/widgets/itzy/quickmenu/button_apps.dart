import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/classes/app_items.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import 'button_window_app.dart';

class AppsButton extends StatelessWidget {
  const AppsButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(actionName: "Apps", icon: const Icon(Icons.apps), child: () => const QuickMenuApps());
  }
}

class QuickMenuApps extends StatefulWidget {
  const QuickMenuApps({super.key});

  @override
  State<QuickMenuApps> createState() => _QuickMenuAppsState();
}

class _QuickMenuAppsState extends State<QuickMenuApps> {
  static const double _categoryHorizontalPadding = 10;

  void _toggleCategory(AppCategory category) {
    final List<AppCategory> categories = List<AppCategory>.from(Boxes.appCategories);
    final int categoryIndex = categories.indexWhere(
      (AppCategory item) => identical(item, category),
    );
    if (categoryIndex == -1) return;

    categories[categoryIndex].isCollapsed = !categories[categoryIndex].isCollapsed;
    Boxes.appCategories = categories;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<AppCategory> categories = Boxes.appCategories;

    bool hasAnyItems = false;
    for (final AppCategory cat in categories) {
      if (cat.items.isNotEmpty || (cat.folderPath != null && cat.folderPath!.isNotEmpty)) {
        hasAnyItems = true;
        break;
      }
    }

    if (!hasAnyItems) {
      final Color accent = Theme.of(context).colorScheme.primary;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        PanelHeader(title: "Apps", accent: accent, icon: Icons.apps),
        Flexible(
            child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.apps_rounded, size: 48, color: userSettings.themeColors.accentColor.withAlpha(80)),
                const SizedBox(height: 16),
                const Text(
                  "Your Apps",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Store your favorite applications and tools here for quick access. Organize them into categories and choose between list or grid views.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Configure them in QuickMenu settings.",
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: accent.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ))
      ]);
    }

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          PanelHeader(title: "Apps", accent: userSettings.themeColors.accentColor, icon: Icons.apps),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final AppCategory category in categories) _buildCategory(category),
                  const SizedBox(height: 10)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(AppCategory category) {
    final List<AppItem> items = List<AppItem>.from(category.items);
    if (category.folderPath != null && category.folderPath!.isNotEmpty) {
      final Directory dir = Directory(category.folderPath!);
      final bool isDesktop = category.folderPath!.toLowerCase().endsWith("desktop");

      if (dir.existsSync()) {
        final List<FileSystemEntity> files = dir.listSync();
        for (final FileSystemEntity file in files) {
          final bool isAllowedFile =
              file is File && (file.path.endsWith(".exe") || file.path.endsWith(".lnk") || file.path.endsWith(".url"));

          if (isDesktop || isAllowedFile) {
            if (category.items.any((AppItem a) => a.path == file.path)) continue;

            final int sepIdx = file.path.lastIndexOf('\\');
            final String rawName = sepIdx >= 0 ? file.path.substring(sepIdx + 1) : file.path;

            String displayName = rawName;
            if (file is File) {
              displayName = rawName.replaceFirst(RegExp(r'\.(exe|lnk|url)$', caseSensitive: false), "");
            }

            items.add(AppItem(
              name: displayName,
              path: file.path,
            ));
          }
        }
        // items.sort((AppItem a, AppItem b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }

    if (items.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _categoryHorizontalPadding,
            10,
            _categoryHorizontalPadding,
            0,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _toggleCategory(category),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: category.isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (DragStartDetails details) {
                        windowManager.startDragging();
                      },
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${items.length}",
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(iconTheme: Theme.of(context).iconTheme.copyWith(size: 20)),
          child: AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            sizeCurve: Curves.easeInOut,
            crossFadeState: category.isCollapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: const SizedBox.shrink(),
            secondChild: category.viewType == AppCategoryViewType.grid
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _categoryHorizontalPadding,
                      8,
                      _categoryHorizontalPadding,
                      0,
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: items.map((AppItem item) => _buildAppItem(item)).toList(),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(_categoryHorizontalPadding, 8, _categoryHorizontalPadding, 0),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _buildAppItem(items[index], isList: true);
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppItem(AppItem item, {bool isList = false}) {
    if (isList) {
      return ListTile(
        dense: true,
        minVerticalPadding: 0,
        minTileHeight: 30,
        minLeadingWidth: 10,
        leading: IgnorePointer(
          ignoring: true,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: WindowsAppButton(path: item.path),
            ),
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _launchApp(item),
      );
    }
    return CustomTooltip(
      message: item.name,
      verticalOffset: 20,
      waitDuration: Duration.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
          highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          onTap: () => _launchApp(item),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Center(
              child: IgnorePointer(
                ignoring: true,
                child: RepaintBoundary(
                  child: WindowsAppButton(
                    path: item.path,
                    arguments: item.arguments,
                    placeholder: const SizedBox(width: 32, height: 32),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _launchApp(AppItem item) {
    WinUtils.open(item.path, arguments: item.arguments);
    QuickMenuFunctions.toggleQuickMenu(visible: false);
  }
}
