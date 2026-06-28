import 'dart:io';

import 'package:tabamewin32/tabamewin32.dart' show BrowserTab;

import '../../../models/win32/window.dart';
import '../../../widgets/itzy/quickmenu/button_notion.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../result/result_item_bookmark.dart';
import 'launcher_result.dart';

typedef LauncherFileOpen = void Function(String path, {int? nodeId});
typedef LauncherAppOpen = void Function(LauncherAppResult app, {int? nodeId});

class LauncherResultExecutor {
  const LauncherResultExecutor({
    required this.onShortcut,
    required this.onBrowseFolder,
    required this.onOpenFile,
    required this.onOpenApp,
    required this.onOpenWindow,
    required this.onOpenBrowserTab,
    required this.onOpenBookmark,
    required this.onOpenNotion,
    required this.onRunAction,
  });

  final void Function(LauncherShortcut shortcut) onShortcut;
  final void Function(String folderPath) onBrowseFolder;
  final LauncherFileOpen onOpenFile;
  final LauncherAppOpen onOpenApp;
  final void Function(Window window) onOpenWindow;
  final void Function(BrowserTab browserTab) onOpenBrowserTab;
  final void Function(BookmarkSearchResult result) onOpenBookmark;
  final void Function(NotionResult result) onOpenNotion;
  final void Function(QuickActionMenuEntry action) onRunAction;

  void execute(LauncherSearchResultItem result) {
    switch (result) {
      case LauncherUtilityResult(shortcut: final LauncherShortcut shortcut?) when result.isShortcut:
        onShortcut(shortcut);
      case LauncherFileResult(entity: final FileSystemEntity entity?) when result.isFile:
        if (entity is Directory) {
          onBrowseFolder(entity.path);
        } else {
          onOpenFile(entity.path, nodeId: result.nodeId);
        }
      case LauncherFileResult(appResult: final LauncherAppResult appResult?) when result.isApp:
        onOpenApp(appResult, nodeId: result.nodeId);
      case LauncherFileResult():
        return;
      case LauncherWindowResult(window: final Window window):
        onOpenWindow(window);
      case LauncherBrowserTabResult(browserTab: final BrowserTab browserTab):
        onOpenBrowserTab(browserTab);
      case LauncherBookmarkResult(bookmarkResult: final BookmarkSearchResult bookmarkResult?) when result.isBookmark:
        onOpenBookmark(bookmarkResult);
      case LauncherBookmarkResult(notionResult: final NotionResult notionResult?) when result.isNotion:
        onOpenNotion(notionResult);
      case LauncherBookmarkResult():
        return;
      case LauncherActionResult(quickAction: final QuickActionMenuEntry quickAction):
        onRunAction(quickAction);
      case LauncherUtilityResult():
        return;
    }
  }
}
