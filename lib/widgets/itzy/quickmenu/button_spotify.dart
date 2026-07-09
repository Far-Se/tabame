import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart' show MediaSession;

import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/util/spotify_controller.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

/// Top-bar launcher for the Spotify controller. Keeps to the thin-button
/// convention: label, icon, modal entry point only — all state lives in
/// [SpotifyPanel].
class SpotifyButton extends StatelessWidget {
  const SpotifyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Spotify",
      icon: const Icon(Icons.music_note_rounded, size: 16),
      onTap: () => showQuickMenuModal(
        context: context,
        maxWidth: 340,
        child: const SpotifyPanel(),
      ),
      // Quick transport straight from the top bar without opening the panel.
      onSecondaryTap: () async {
        final MediaSession? s = await SpotifyController.fetchSession();
        await SpotifyController.command(s, SpotifyController.cmdTogglePlayPause);
      },
      onTertiaryTapDown: (_) async {
        final MediaSession? s = await SpotifyController.fetchSession();
        await SpotifyController.command(s, SpotifyController.cmdNext);
      },
    );
  }
}

class SpotifyPanel extends StatefulWidget {
  const SpotifyPanel({super.key});

  @override
  State<SpotifyPanel> createState() => _SpotifyPanelState();
}

class _SpotifyPanelState extends State<SpotifyPanel> {
  MediaSession? _session;
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep now-playing + play/pause state fresh while the panel is open.
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final MediaSession? session = await SpotifyController.fetchSession();
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  Future<void> _send(String command) async {
    await SpotifyController.command(_session, command);
    // SMTC updates its state asynchronously after a command; re-read shortly
    // after so the artwork/title/play-state reflect the new track.
    Future<void>.delayed(const Duration(milliseconds: 300), () => _refresh(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        PanelHeader(
          title: "Spotify",
          icon: Icons.music_note_rounded,
          buttonPressed: () => _refresh(),
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: "Refresh",
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: _buildBody(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _session == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_session == null) return _buildEmpty();
    return _buildPlayer(_session!);
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.music_off_rounded, size: 32, color: Design.text.withAlpha(120)),
          const SizedBox(height: 10),
          Text(
            "Spotify isn't playing",
            style: TextStyle(
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w700,
              color: Design.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Start Spotify to control playback here",
            style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(140)),
          ),
          const SizedBox(height: 16),
          _buildAccentButton(
            label: "Open Spotify",
            icon: Icons.launch_rounded,
            onTap: () {
              SpotifyController.launchApp();
              Future<void>.delayed(const Duration(seconds: 1), () => _refresh());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(MediaSession session) {
    final ImageProvider? art = session.thumbnailImage;
    final String title = session.title.isEmpty ? 'Spotify' : session.title;
    final String artist = session.artist.isEmpty ? 'Unknown artist' : session.artist;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        // Now-playing card.
        Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Design.text.withAlpha(16)),
          ),
          child: Row(
            crossAxisAlignment: C.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: art != null
                      ? Image(image: art, fit: BoxFit.cover)
                      : Container(
                          color: Design.accent.withAlpha(24),
                          child: Icon(Icons.music_note_rounded, size: 28, color: Design.accent),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: C.start,
                  mainAxisAlignment: M.center,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1.5,
                        fontWeight: FontWeight.w700,
                        color: Design.text,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(160)),
                    ),
                    if (session.albumTitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        session.albumTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(110)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Transport controls.
        Row(
          mainAxisAlignment: M.center,
          children: <Widget>[
            _buildTransport(
              icon: Icons.skip_previous_rounded,
              size: 44,
              onTap: () => _send(SpotifyController.cmdPrevious),
            ),
            const SizedBox(width: 14),
            _buildTransport(
              icon: session.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 58,
              primary: true,
              onTap: () => _send(SpotifyController.cmdTogglePlayPause),
            ),
            const SizedBox(width: 14),
            _buildTransport(
              icon: Icons.skip_next_rounded,
              size: 44,
              onTap: () => _send(SpotifyController.cmdNext),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransport({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary ? Design.accent.withAlpha(28) : Design.text.withAlpha(8),
          border: Border.all(
            color: primary ? Design.accent.withAlpha(80) : Design.text.withAlpha(20),
          ),
        ),
        child: Icon(icon, size: size * 0.46, color: primary ? Design.accent : Design.text.withAlpha(210)),
      ),
    );
  }

  Widget _buildAccentButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 18),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Design.accent.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: Design.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Design.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
