import '../../platform/audio_system_service.dart';

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
  static Future<PlatformMediaSession?> fetchSession() async {
    try {
      final PlatformMediaSessionResult result = await MediaSessionService.instance.listSessions();
      for (final PlatformMediaSession session in result.sessions) {
        if (_isSpotifyId(session.id) || _isSpotifyId(session.applicationName)) return session;
      }
    } catch (_) {}
    return null;
  }

  /// Sends [command] to the given Spotify [session]. No-op when [session] is
  /// null or the target adapter cannot express the command.
  static Future<void> command(PlatformMediaSession? session, String command) async {
    if (session == null) return;
    final PlatformMediaCommand? operation = switch (command) {
      cmdTogglePlayPause => PlatformMediaCommand.playPause,
      cmdPlay => PlatformMediaCommand.play,
      cmdPause => PlatformMediaCommand.pause,
      cmdNext => PlatformMediaCommand.next,
      cmdPrevious => PlatformMediaCommand.previous,
      _ => null,
    };
    if (operation == null) return;
    await MediaSessionService.instance.sendCommand(session, operation);
  }

  /// Launches the Spotify desktop app through the platform adapter.
  static Future<bool> launchApp() {
    return MediaSessionService.instance.launchApplication(
      const PlatformMediaBinding(applicationId: 'spotify', applicationPath: 'spotify:'),
    );
  }
}
