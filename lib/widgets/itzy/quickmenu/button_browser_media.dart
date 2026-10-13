import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../services/browser_bridge_service.dart';
import '../../../services/browser_media_service.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class BrowserMediaButton extends StatelessWidget {
  const BrowserMediaButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: 'Browser Media',
      icon: const Icon(Icons.video_library_outlined),
      onTap: () => _openPanel(context),
      onSecondaryTap: () async {
        final BrowserMediaService service = BrowserMediaService.instance;
        service.initialize();
        final bool success = await service.togglePreferred();
        if (!success && context.mounted) _openPanel(context);
      },
    );
  }

  void _openPanel(BuildContext context) {
    unawaited(showQuickMenuModal(context: context, child: const BrowserMediaPanel()));
  }
}

class BrowserMediaPanel extends StatefulWidget {
  const BrowserMediaPanel({super.key});

  @override
  State<BrowserMediaPanel> createState() => _BrowserMediaPanelState();
}

class _BrowserMediaPanelState extends State<BrowserMediaPanel> {
  final BrowserMediaService _service = BrowserMediaService.instance;
  Timer? _poll;
  String _actionError = '';

  @override
  void initState() {
    super.initState();
    _service.initialize();
    unawaited(_service.refresh());
    // Pausing from the browser may not change its audible flag immediately.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_service.refresh()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _activate(BrowserMediaTab tab) async {
    setState(() => _actionError = '');
    try {
      await BrowserBridgeService.instance.request('tabs.activate', params: <String, Object?>{'tabId': tab.id});
      await QuickMenuFunctions.hideQuickMenu();
    } catch (error) {
      if (mounted) setState(() => _actionError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (BuildContext context, Widget? child) {
        final List<BrowserMediaTab> tabs = _service.tabs;
        final List<BrowserMediaTab> playing = tabs.where((BrowserMediaTab tab) => tab.playing).toList();
        final List<BrowserMediaTab> paused = tabs.where((BrowserMediaTab tab) => !tab.playing).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PanelHeader(
              title: 'Browser Media',
              icon: Icons.video_library_outlined,
              buttonIcon: Icons.refresh_rounded,
              buttonTooltip: 'Refresh media tabs',
              buttonPressed: _service.status.connected ? () => unawaited(_service.refresh()) : null,
              extraActions: <Widget>[
                CustomTooltip(
                  message: "Left click: show tabs\nRight click: play / pause last controlled tab",
                  child: IconButton(
                    icon: const Icon(Icons.info),
                    onPressed: () {},
                  ),
                )
              ],
            ),
            if (_service.loading && tabs.isEmpty)
              LinearProgressIndicator(minHeight: 2, color: Design.accent, backgroundColor: Design.accent.withAlpha(12)),
            Flexible(
              child: Material(
                type: MaterialType.transparency,
                child: !_service.status.connected
                    ? ListView(shrinkWrap: true, children: <Widget>[_connectionState()])
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                        children: <Widget>[
                          if (_service.error.isNotEmpty) _errorStrip(_service.error),
                          if (_actionError.isNotEmpty) _errorStrip(_actionError),
                          if (tabs.isEmpty)
                            _emptyState(
                              Icons.music_off_outlined,
                              _service.loading ? 'Finding media tabs...' : 'No media tabs yet',
                              'Play audio in your browser. Paused tabs will stay here.',
                            ),
                          if (playing.isNotEmpty) ...<Widget>[
                            _section('Playing', playing.length, Icons.volume_up_rounded),
                            ...playing.map(_tabRow),
                          ],
                          if (paused.isNotEmpty) ...<Widget>[
                            if (playing.isNotEmpty) const SizedBox(height: 8),
                            _section('Previously playing', paused.length, Icons.history_rounded),
                            ...paused.map(_tabRow),
                          ],
                        ],
                      ),
              ),
            ),
            if (_service.status.connected && tabs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
                child: Text(
                  'Right-click the toolbar button to play / pause your last controlled tab.',
                  style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(145)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _connectionState() {
    final BrowserBridgeStatus status = _service.status;
    return _emptyState(
      Icons.link_off_rounded,
      status.enabled ? 'Browser connector disconnected' : 'Browser integration is off',
      status.error.isNotEmpty
          ? status.error
          : status.enabled
              ? 'Connect the Tabame extension in your browser.'
              : 'Enable Browser integration in Launcher Plugins and pair the Tabame extension.',
    );
  }

  Widget _emptyState(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 28, color: Design.text.withAlpha(100)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: Design.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(155)),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, int count, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 3, 3, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: Design.accent),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
                fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Design.text),
          ),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
          const SizedBox(width: 8),
          Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
        ],
      ),
    );
  }

  Widget _tabRow(BrowserMediaTab tab) {
    final bool busy = _service.isBusy(tab.id);
    final String action = tab.playing ? 'Pause' : 'Play';
    return Padding(
      key: ValueKey<int>(tab.id),
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        decoration: BoxDecoration(
          color: tab.playing ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tab.playing ? Design.accent.withAlpha(35) : Design.text.withAlpha(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 5, 5),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: busy
                        ? Padding(
                            padding: const EdgeInsets.all(9),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Design.accent))
                        : IconButton(
                            tooltip: '$action ${tab.title}',
                            onPressed: () => unawaited(_service.toggle(tab.id)),
                            icon: Icon(tab.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 21, color: Design.accent),
                            padding: EdgeInsets.zero,
                          ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${tab.host}${tab.muted ? ' · Muted' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(145)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tab.muted ? 'Unmute tab' : 'Mute tab',
                    onPressed: busy ? null : () => unawaited(_service.toggleMute(tab.id)),
                    icon: Icon(
                      tab.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 17,
                      color: busy
                          ? Design.text.withAlpha(70)
                          : tab.muted
                              ? Design.accent
                              : Design.text.withAlpha(160),
                    ),
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    tooltip: 'Switch to tab',
                    onPressed: () => unawaited(_activate(tab)),
                    icon: Icon(Icons.open_in_new_rounded, size: 15, color: Design.text.withAlpha(160)),
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (tab.error.isNotEmpty) _errorStrip(tab.error),
            if (tab.notice.isNotEmpty) _errorStrip(tab.notice),
          ],
        ),
      ),
    );
  }

  Widget _errorStrip(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 13, color: Design.accent),
          const SizedBox(width: 6),
          Expanded(
              child: Text(message, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(190)))),
        ],
      ),
    );
  }
}
