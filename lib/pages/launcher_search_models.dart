import 'dart:io';
import 'package:flutter/material.dart';
import '../models/win32/window.dart';
import '../widgets/itzy/quickmenu/button_notion.dart';
import '../widgets/itzy/quickmenu/button_quickactions.dart';
import 'interface/result_item_bookmark.dart';

enum LauncherSearchMode {
  mixed,
  actionsOnly,
  filesOnly,
  windowsOnly,
  bookmarksOnly,
  bookmarkOnly,
  cliOnly,
  appsOnly,
  desktopOnly,
  notionOnly,
  timerCommand,
  functionCommand,
}

class LauncherShortcut {
  final String label;
  final String caption;
  final String prefix;
  final IconData icon;

  const LauncherShortcut({
    required this.label,
    required this.caption,
    required this.prefix,
    required this.icon,
  });
}

class LauncherInfoResult {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const LauncherInfoResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class LauncherSearchResultItem {
  const LauncherSearchResultItem.file(this.entity, [this.nodeId])
      : quickAction = null,
        window = null,
        bookmarkResult = null,
        notionResult = null,
        infoResult = null,
        shortcut = null;

  const LauncherSearchResultItem.quickAction(this.quickAction)
      : entity = null,
        nodeId = null,
        window = null,
        bookmarkResult = null,
        notionResult = null,
        infoResult = null,
        shortcut = null;

  const LauncherSearchResultItem.window(this.window)
      : entity = null,
        nodeId = null,
        quickAction = null,
        bookmarkResult = null,
        notionResult = null,
        infoResult = null,
        shortcut = null;

  const LauncherSearchResultItem.bookmark(this.bookmarkResult)
      : entity = null,
        nodeId = null,
        quickAction = null,
        window = null,
        notionResult = null,
        infoResult = null,
        shortcut = null;

  const LauncherSearchResultItem.notion(this.notionResult)
      : entity = null,
        nodeId = null,
        quickAction = null,
        window = null,
        bookmarkResult = null,
        infoResult = null,
        shortcut = null;

  const LauncherSearchResultItem.shortcut(this.shortcut)
      : entity = null,
        nodeId = null,
        quickAction = null,
        window = null,
        bookmarkResult = null,
        notionResult = null,
        infoResult = null;

  const LauncherSearchResultItem.info(this.infoResult)
      : entity = null,
        nodeId = null,
        quickAction = null,
        window = null,
        bookmarkResult = null,
        notionResult = null,
        shortcut = null;

  final FileSystemEntity? entity;
  final int? nodeId;
  final QuickActionMenuEntry? quickAction;
  final Window? window;
  final BookmarkSearchResult? bookmarkResult;
  final NotionResult? notionResult;
  final LauncherInfoResult? infoResult;
  final LauncherShortcut? shortcut;

  bool get isFile => entity != null;
  bool get isWindow => window != null;
  bool get isBookmark => bookmarkResult != null;
  bool get isNotion => notionResult != null;
  bool get isInfo => infoResult != null;
  bool get isShortcut => shortcut != null;

  String get id => isFile
      ? 'file:${entity!.path}'
      : isWindow
          ? 'window:${window!.hWnd}'
          : isBookmark
              ? 'bookmark:${bookmarkResult!.id}'
              : isNotion
                  ? 'notion:${notionResult!.id}'
                  : isInfo
                      ? 'info:${infoResult!.id}'
                      : isShortcut
                          ? 'shortcut:${shortcut!.prefix}'
                          : 'quick:${quickAction!.id}';
}
