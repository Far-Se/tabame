import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart' show BrowserTab;

import '../../../models/win32/window.dart';
import '../../../widgets/itzy/quickmenu/button_notion.dart';
import '../../../widgets/itzy/quickmenu/button_obsidian.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../../widgets/itzy/quickmenu/button_steam.dart';
import '../result/result_item_bookmark.dart';

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

class LauncherAppResult {
  final String name;
  final String launchTarget;
  final String appUserModelId;
  final String parsingName;
  final String subtitle;
  final String stableIdentity;

  const LauncherAppResult({
    required this.name,
    required this.launchTarget,
    required this.appUserModelId,
    required this.parsingName,
    required this.subtitle,
    required this.stableIdentity,
  });

  String get iconCacheKey => appUserModelId.hashCode.toString();
}

sealed class LauncherSearchResultItem {
  const LauncherSearchResultItem();

  const factory LauncherSearchResultItem.file(FileSystemEntity entity, [int? nodeId]) = LauncherFileResult.file;
  const factory LauncherSearchResultItem.app(LauncherAppResult appResult, [int? nodeId]) = LauncherFileResult.app;
  const factory LauncherSearchResultItem.quickAction(QuickActionMenuEntry quickAction) = LauncherActionResult;
  const factory LauncherSearchResultItem.window(Window window) = LauncherWindowResult;
  const factory LauncherSearchResultItem.browserTab(BrowserTab browserTab) = LauncherBrowserTabResult;
  const factory LauncherSearchResultItem.bookmark(BookmarkSearchResult bookmarkResult) =
      LauncherBookmarkResult.bookmark;
  const factory LauncherSearchResultItem.notion(NotionResult notionResult) = LauncherBookmarkResult.notion;
  const factory LauncherSearchResultItem.obsidian(ObsidianNote obsidianResult) = LauncherObsidianResult;
  const factory LauncherSearchResultItem.steam(SteamGame steamResult) = LauncherSteamResult;
  const factory LauncherSearchResultItem.shortcut(LauncherShortcut shortcut) = LauncherUtilityResult.shortcut;
  const factory LauncherSearchResultItem.info(LauncherInfoResult infoResult) = LauncherUtilityResult.info;

  FileSystemEntity? get entity => null;
  int? get nodeId => null;
  LauncherAppResult? get appResult => null;
  QuickActionMenuEntry? get quickAction => null;
  Window? get window => null;
  BrowserTab? get browserTab => null;
  BookmarkSearchResult? get bookmarkResult => null;
  NotionResult? get notionResult => null;
  ObsidianNote? get obsidianResult => null;
  SteamGame? get steamResult => null;
  LauncherInfoResult? get infoResult => null;
  LauncherShortcut? get shortcut => null;

  bool get isFile => false;
  bool get isApp => false;
  bool get isWindow => false;
  bool get isBrowserTab => false;
  bool get isBookmark => false;
  bool get isNotion => false;
  bool get isObsidian => false;
  bool get isSteam => false;
  bool get isInfo => false;
  bool get isShortcut => false;

  String get id;
}

final class LauncherFileResult extends LauncherSearchResultItem {
  const LauncherFileResult.file(this.entity, [this.nodeId]) : appResult = null;
  const LauncherFileResult.app(this.appResult, [this.nodeId]) : entity = null;

  @override
  final FileSystemEntity? entity;

  @override
  final int? nodeId;

  @override
  final LauncherAppResult? appResult;

  @override
  bool get isFile => entity != null;

  @override
  bool get isApp => appResult != null;

  @override
  String get id => isApp ? 'app:${appResult!.appUserModelId}' : 'file:${entity!.path}';
}

final class LauncherActionResult extends LauncherSearchResultItem {
  const LauncherActionResult(this.quickAction);

  @override
  final QuickActionMenuEntry quickAction;

  @override
  String get id => 'quick:${quickAction.id}';
}

final class LauncherBookmarkResult extends LauncherSearchResultItem {
  const LauncherBookmarkResult.bookmark(this.bookmarkResult) : notionResult = null;
  const LauncherBookmarkResult.notion(this.notionResult) : bookmarkResult = null;

  @override
  final BookmarkSearchResult? bookmarkResult;

  @override
  final NotionResult? notionResult;

  @override
  bool get isBookmark => bookmarkResult != null;

  @override
  bool get isNotion => notionResult != null;

  @override
  String get id => isNotion ? 'notion:${notionResult!.id}' : 'bookmark:${bookmarkResult!.id}';
}

final class LauncherObsidianResult extends LauncherSearchResultItem {
  const LauncherObsidianResult(this.obsidianResult);

  @override
  final ObsidianNote obsidianResult;

  @override
  bool get isObsidian => true;

  @override
  String get id => 'obsidian:${obsidianResult.absolutePath}';
}

final class LauncherSteamResult extends LauncherSearchResultItem {
  const LauncherSteamResult(this.steamResult);

  @override
  final SteamGame steamResult;

  @override
  bool get isSteam => true;

  @override
  String get id => 'steam:${steamResult.appId}';
}

final class LauncherWindowResult extends LauncherSearchResultItem {
  const LauncherWindowResult(this.window);

  @override
  final Window window;

  @override
  bool get isWindow => true;

  @override
  String get id => 'window:${window.hWnd}';
}

final class LauncherBrowserTabResult extends LauncherSearchResultItem {
  const LauncherBrowserTabResult(this.browserTab);

  @override
  final BrowserTab browserTab;

  @override
  bool get isBrowserTab => true;

  @override
  String get id => 'browserTab:${browserTab.hWnd}:${browserTab.index}';
}

final class LauncherUtilityResult extends LauncherSearchResultItem {
  const LauncherUtilityResult.shortcut(this.shortcut) : infoResult = null;
  const LauncherUtilityResult.info(this.infoResult) : shortcut = null;

  @override
  final LauncherShortcut? shortcut;

  @override
  final LauncherInfoResult? infoResult;

  @override
  bool get isShortcut => shortcut != null;

  @override
  bool get isInfo => infoResult != null;

  @override
  String get id => isShortcut ? 'shortcut:${shortcut!.prefix}' : 'info:${infoResult!.id}';
}
