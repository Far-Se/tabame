import 'package:tabamewin32/tabamewin32.dart' show MediaSession, MediaSessionPlugin, MediaSessionResult;

import '../win32/win_utils.dart';

/// Thin wrapper over the SMTC (System Media Transport Controls) media session
/// plugin, scoped to the Spotify desktop app. Both the launcher `sp ` mode and
/// the [SpotifyButton] quick-menu panel read the current track and drive
/// transport controls through here, so the matching/command logic lives in one
/// place.
///
/// This intentionally uses SMTC rather than the Spotify Web API: it needs no
/// OAuth, no developer app, works offline, and reuses the plugin that already
/// powers the media-control button. The tradeoff is that only what Spotify
/// publishes to SMTC is available (now-playing metadata, artwork, and
/// play/pause/next/previous) — no library search, playlists, or device volume.
class SpotifyController {
  const SpotifyController._();

  /// SMTC command strings understood by the native `mediaSessionCommand`
  /// handler (see `tabamewin32/windows/media_session.cpp`).
  static const String cmdTogglePlayPause = 'togglePlayPause';
  static const String cmdPlay = 'play';
  static const String cmdPause = 'pause';
  static const String cmdNext = 'skipNext';
  static const String cmdPrevious = 'skipPrevious';

  /// A SourceAppUserModelId belongs to Spotify when it mentions "spotify".
  /// Covers both the classic desktop installer (`Spotify.exe`) and the
  /// Microsoft Store build (`SpotifyAB.SpotifyMusic_...!Spotify`).
  static bool _isSpotifyId(String id) => id.toLowerCase().contains('spotify');

  /// Returns the current Spotify SMTC session, or null when Spotify isn't
  /// running / hasn't registered a session yet.
  static Future<MediaSession?> fetchSession() async {
    try {
      final MediaSessionResult result = await MediaSessionPlugin.getMediaSessions();
      for (final MediaSession session in result.sessions) {
        if (_isSpotifyId(session.id)) return session;
      }
    } catch (_) {}
    return null;
  }

  /// Sends [command] to the given Spotify [session]. No-op when [session] is
  /// null.
  static Future<void> command(MediaSession? session, String command) async {
    if (session == null) return;
    await MediaSessionPlugin.sendCommand(session.id, command);
  }

  /// Launches the Spotify desktop app via its URI protocol.
  static void launchApp() => WinUtils.open('spotify:');
}
