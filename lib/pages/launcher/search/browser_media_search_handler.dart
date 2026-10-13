import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../services/browser_bridge_service.dart';
import '../../../services/browser_media_service.dart';
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';

class BrowserMediaSearchHandler {
  BrowserMediaSearchHandler._(this.context);

  final LauncherSearchContext context;
  final BrowserMediaService _service = BrowserMediaService.instance;
  int? _busyTabId;

  bool get _active =>
      !context.isDisposed &&
      QuickMenuFunctions.isQuickMenuVisible &&
      user.launcherSearchText == context.query &&
      context.isActiveSearch(context.requestId, context.query);

  static void handle(LauncherSearchContext context) {
    final BrowserMediaSearchHandler handler = BrowserMediaSearchHandler._(context);
    handler._service.initialize();
    handler._publish(loading: true);
    unawaited(handler._refresh());
  }

  Future<void> _refresh() async {
    if (!_active) return;
    await _service.refresh();
    if (!_active) return;
    _publish();
    // Keep external playback changes current. A stale or hidden search stops
    // at the next tick, and scheduling after the read prevents overlapping polls.
    Timer(const Duration(seconds: 2), () => unawaited(_refresh()));
  }

  void _publish({bool loading = false}) {
    if (!_active) return;
    final BrowserBridgeStatus status = _service.status;
    if (!status.connected) {
      context.setResults(<LauncherSearchResultItem>[
        _info(
          'connection',
          status.enabled ? 'Browser connector disconnected' : 'Browser integration is off',
          status.error.isNotEmpty
              ? status.error
              : status.enabled
                  ? 'Connect the Tabame extension in your browser.'
                  : 'Enable Browser integration in Launcher Plugins and pair the Tabame extension.',
        ),
      ], resetSelection: false);
      return;
    }

    final String filter = context.lowerQuery.trim();
    final List<BrowserMediaTab> tabs = _service.tabs;
    final List<BrowserMediaTab> matches =
        tabs.where((BrowserMediaTab tab) => '${tab.title} ${tab.url}'.toLowerCase().contains(filter)).toList();
    final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[
      if (_service.error.isNotEmpty) _info('error', 'Unable to refresh media tabs', _service.error),
    ];
    for (final BrowserMediaTab tab in matches) {
      final bool busy = _busyTabId == tab.id || _service.isBusy(tab.id);
      final String action = busy
          ? 'Updating'
          : tab.playing
              ? 'Pause'
              : 'Play';
      results.add(_action(
        id: 'tab:${tab.id}',
        title: '$action · ${tab.title}${tab.muted ? ' · Muted' : ''}',
        subtitle: '${tab.host} · ${tab.playing ? 'Playing' : 'Previously playing'}',
        icon: busy
            ? Icons.hourglass_top_rounded
            : tab.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
        onExecute: () => unawaited(_interact(tab.id)),
      ));
      if (tab.error.isNotEmpty) results.add(_info('error:${tab.id}', tab.error, tab.title));
      if (tab.notice.isNotEmpty) results.add(_info('notice:${tab.id}', tab.notice, tab.title));
      if (tab.muted) {
        results.add(_action(
          id: 'unmute:${tab.id}',
          title: 'Unmute · ${tab.title}',
          subtitle: 'Restore audio for this tab',
          icon: Icons.volume_up_rounded,
          onExecute: () => unawaited(_interact(tab.id, unmute: true)),
        ));
      }
    }
    if (results.isEmpty) {
      results.add(_info(
        'empty',
        loading
            ? 'Finding media tabs...'
            : tabs.isEmpty
                ? 'No media tabs yet'
                : 'No matching media tabs',
        tabs.isEmpty
            ? 'Play audio in your browser. Paused tabs stay available here.'
            : 'Filter by tab title or site, or type bm to show all media tabs.',
      ));
    }
    context.setResults(results, isSearching: loading, resetSelection: false);
  }

  Future<void> _interact(int tabId, {bool unmute = false}) async {
    if (!_active || _busyTabId != null || _service.isBusy(tabId)) return;
    if (unmute && !_service.tabs.any((BrowserMediaTab tab) => tab.id == tabId && tab.muted)) return;
    _busyTabId = tabId;
    _publish();
    try {
      if (unmute) {
        await _service.toggleMute(tabId);
      } else {
        await _service.toggle(tabId);
      }
    } finally {
      _busyTabId = null;
      // Keep the launcher open and preserve the selected tab as playback state
      // changes its position. Pause-to-mute notices remain visible in the list.
      _publish();
    }
  }

  static LauncherSearchResultItem _action({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onExecute,
  }) =>
      LauncherSearchResultItem.quickAction(QuickActionMenuEntry(
        id: 'browser-media:$id',
        title: title,
        searchTerms: <String>[title, subtitle],
        iconBuilder: (BuildContext context) => Icon(icon, color: Design.accent, size: 20),
        onExecute: onExecute,
        allowRenderedFallbackExecute: false,
        builder: (BuildContext context) => ListTile(
          dense: true,
          leading: Icon(icon, color: Design.accent, size: 20),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onExecute,
        ),
      ));

  static LauncherSearchResultItem _info(String id, String title, String subtitle) =>
      LauncherSearchResultItem.info(LauncherInfoResult(
        id: 'browser-media:$id',
        title: title,
        subtitle: subtitle,
        icon: Icons.video_library_outlined,
      ));
}
