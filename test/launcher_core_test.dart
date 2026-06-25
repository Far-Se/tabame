import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/app_items.dart';
import 'package:tabame/models/classes/saved_maps.dart';
import 'package:tabame/pages/launcher/core/launcher_query.dart';
import 'package:tabame/pages/launcher/core/launcher_result.dart';
import 'package:tabame/pages/launcher/result/result_item_bookmark.dart';
import 'package:tabame/widgets/itzy/quickmenu/button_notion.dart';
import 'package:tabame/widgets/itzy/quickmenu/button_quickactions.dart';

void main() {
  group('LauncherQuery', () {
    test('parses launcher prefixes and normalized query text', () {
      final Map<String, (LauncherSearchMode, String)> cases = <String, (LauncherSearchMode, String)>{
        '/reload': (LauncherSearchMode.actionsOnly, 'reload'),
        '.chrome': (LauncherSearchMode.windowsOnly, 'chrome'),
        '> main.dart': (LauncherSearchMode.filesOnly, 'main.dart'),
        '? notes': (LauncherSearchMode.filesOnly, 'notes'),
        ' notes': (LauncherSearchMode.filesOnly, 'notes'),
        '; desktop': (LauncherSearchMode.desktopOnly, 'desktop'),
        "' docs": (LauncherSearchMode.bookmarksOnly, 'docs'),
        'b docs': (LauncherSearchMode.bookmarkOnly, 'docs'),
        'cli build': (LauncherSearchMode.cliOnly, 'build'),
        'app figma': (LauncherSearchMode.appsOnly, 'figma'),
        'n roadmap': (LauncherSearchMode.notionOnly, 'roadmap'),
        r'$timer 1 stretch': (LauncherSearchMode.functionCommand, 'timer 1 stretch'),
        'timer 1 stretch': (LauncherSearchMode.timerCommand, '1 stretch'),
        'plain': (LauncherSearchMode.mixed, 'plain'),
      };

      for (final MapEntry<String, (LauncherSearchMode, String)> entry in cases.entries) {
        final LauncherQuery query = LauncherQuery.parse(entry.key);
        expect(query.mode, entry.value.$1, reason: entry.key);
        expect(query.normalized, entry.value.$2, reason: entry.key);
      }
    });

    test('treats empty mixed query as empty launcher input', () {
      expect(LauncherQuery.parse('').isEmpty, isTrue);
      expect(LauncherQuery.parse('   ').isEmpty, isFalse);
      expect(LauncherQuery.parse('/').isEmpty, isFalse);
    });
  });

  group('LauncherSearchResultItem ids', () {
    test('builds stable ids for file-family results', () {
      expect(LauncherSearchResultItem.file(File(r'C:\Temp\note.txt')).id, r'file:C:\Temp\note.txt');

      const LauncherAppResult app = LauncherAppResult(
        name: 'Calculator',
        launchTarget: r'shell:AppsFolder\calculator',
        appUserModelId: 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App',
        parsingName: '',
        subtitle: 'Calculator',
        stableIdentity: 'calculator||',
      );
      expect(
        const LauncherSearchResultItem.app(app).id,
        'app:Microsoft.WindowsCalculator_8wekyb3d8bbwe!App',
      );
    });

    test('builds stable ids for action and utility results', () {
      final QuickActionMenuEntry action = QuickActionMenuEntry(
        id: 'custom-action',
        title: 'Custom',
        searchTerms: const <String>['custom'],
        builder: (_) => const SizedBox.shrink(),
      );
      expect(LauncherSearchResultItem.quickAction(action).id, 'quick:custom-action');

      const LauncherShortcut shortcut = LauncherShortcut(
        label: '/',
        caption: 'Quick Action',
        prefix: '/',
        icon: IconData(0xe145, fontFamily: 'MaterialIcons'),
      );
      expect(const LauncherSearchResultItem.shortcut(shortcut).id, 'shortcut:/');

      const LauncherInfoResult info = LauncherInfoResult(
        id: 'help',
        title: 'Help',
        subtitle: 'Useful hint',
        icon: IconData(0xe88e, fontFamily: 'MaterialIcons'),
      );
      expect(const LauncherSearchResultItem.info(info).id, 'info:help');
    });

    test('builds stable ids for bookmark-family results', () {
      final BookmarkSearchResult bookmark = BookmarkSearchResult.bookmark(
        BookmarkInfo(emoji: '', title: 'Docs', stringToExecute: 'https://example.com'),
      );
      expect(LauncherSearchResultItem.bookmark(bookmark).id, 'bookmark:bm:Docs');

      final BookmarkSearchResult cli = BookmarkSearchResult.cli(
        CliBookItem(key: 'build', value: 'flutter build windows'),
      );
      expect(LauncherSearchResultItem.bookmark(cli).id, 'bookmark:cli:build');

      final BookmarkSearchResult app = BookmarkSearchResult.app(
        AppItem(name: 'Figma', path: r'C:\Apps\Figma.exe'),
      );
      expect(LauncherSearchResultItem.bookmark(app).id, r'bookmark:app:C:\Apps\Figma.exe');

      final NotionResult notion = NotionResult(
        id: 'notion-page',
        title: 'Roadmap',
        url: 'https://notion.so/page',
        objectType: 'page',
      );
      expect(LauncherSearchResultItem.notion(notion).id, 'notion:notion-page');
    });
  });
}
