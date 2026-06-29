import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A single Windows Terminal profile parsed from `settings.json`.
class TerminalProfile {
  const TerminalProfile({
    required this.name,
    required this.guid,
    this.icon,
    this.commandline,
  });

  final String name;
  final String guid;

  /// Either a file path or an emoji glyph, as stored in the profile.
  final String? icon;

  /// The command the profile runs, shown as a hint subtitle when present.
  final String? commandline;

  /// Arguments that launch this profile in a new Windows Terminal window.
  /// Prefer the GUID (stable, unique) and fall back to the display name.
  String get launchArguments => guid.isNotEmpty ? '-p "$guid"' : '-p "$name"';
}

/// Locates Windows Terminal's `settings.json` and parses its profile list.
///
/// `settings.json` is JSONC (allows `//` and `/* */` comments plus trailing
/// commas), so the raw text is sanitised before decoding. Profiles can live
/// either directly under `profiles` (legacy) or under `profiles.list`
/// (current); both shapes are handled. Hidden profiles are skipped.
class WindowsTerminalService {
  static List<TerminalProfile>? _cached;
  static String? _cachedForPath;

  static void invalidateCache() {
    _cached = null;
    _cachedForPath = null;
  }

  /// The candidate `settings.json` locations, most common first: the Store
  /// build, the Preview build, then the unpackaged/portable install.
  static List<String> _candidatePaths() {
    final String localAppData =
        Platform.environment['LOCALAPPDATA'] ?? p.join(Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Local');
    return <String>[
      p.join(localAppData, 'Packages', 'Microsoft.WindowsTerminal_8wekyb3d8bbwe', 'LocalState', 'settings.json'),
      p.join(localAppData, 'Packages', 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe', 'LocalState', 'settings.json'),
      p.join(localAppData, 'Microsoft', 'Windows Terminal', 'settings.json'),
    ];
  }

  static String? _findSettingsFile() {
    for (final String path in _candidatePaths()) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// True when Windows Terminal appears to be installed (a settings file or the
  /// `wt.exe` launcher is present). Used to decide whether to surface the `t `
  /// mode at all.
  static bool get isAvailable => _findSettingsFile() != null;

  /// Strips JSONC comments and trailing commas so `jsonDecode` accepts the file.
  /// String literals are preserved verbatim so `//` or `,` inside values stay.
  static String _stripJsonc(String input) {
    final StringBuffer out = StringBuffer();
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < input.length; i++) {
      final String c = input[i];
      if (inString) {
        out.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        continue;
      }
      // Line comment.
      if (c == '/' && i + 1 < input.length && input[i + 1] == '/') {
        while (i < input.length && input[i] != '\n') {
          i++;
        }
        if (i < input.length) out.write('\n');
        continue;
      }
      // Block comment.
      if (c == '/' && i + 1 < input.length && input[i + 1] == '*') {
        i += 2;
        while (i + 1 < input.length && !(input[i] == '*' && input[i + 1] == '/')) {
          i++;
        }
        i++; // Skip the closing '/'.
        continue;
      }
      out.write(c);
    }

    // Remove trailing commas before } or ].
    return out.toString().replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
  }

  static List<dynamic>? _profileEntries(dynamic profiles) {
    if (profiles is List) return profiles;
    if (profiles is Map && profiles['list'] is List) return profiles['list'] as List<dynamic>;
    return null;
  }

  /// Reads and parses every visible Windows Terminal profile, ordered as they
  /// appear in `settings.json`. Cached per settings-file path; pass
  /// [forceRefresh] to re-read after the user edits their profiles.
  static Future<List<TerminalProfile>> scan({bool forceRefresh = false}) async {
    final String? settingsPath = _findSettingsFile();
    if (settingsPath == null) return <TerminalProfile>[];

    if (!forceRefresh && _cached != null && _cachedForPath == settingsPath) {
      return _cached!;
    }

    final List<TerminalProfile> profiles = <TerminalProfile>[];
    try {
      final String raw = await File(settingsPath).readAsString();
      final dynamic decoded = jsonDecode(_stripJsonc(raw));
      final List<dynamic>? entries = decoded is Map ? _profileEntries(decoded['profiles']) : null;
      if (entries != null) {
        for (final dynamic entry in entries) {
          if (entry is! Map) continue;
          if (entry['hidden'] == true) continue;
          final String name = (entry['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          profiles.add(TerminalProfile(
            name: name,
            guid: (entry['guid'] ?? '').toString().trim(),
            icon: entry['icon']?.toString(),
            commandline: entry['commandline']?.toString(),
          ));
        }
      }
    } catch (_) {
      // A malformed settings file yields an empty list rather than throwing.
    }

    _cached = profiles;
    _cachedForPath = settingsPath;
    return profiles;
  }

  static List<TerminalProfile> filter(List<TerminalProfile> profiles, String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return profiles;
    return profiles.where((TerminalProfile profile) => profile.name.toLowerCase().contains(q)).toList();
  }
}
