/// Describes a single user-installed launcher plugin, parsed from the
/// `plugin.json` that lives in each `%localappdata%\Tabame\plugins\<id>\` folder.
///
/// A plugin is an external script (Python / Node / Bun) that Tabame launches as
/// a long-running child process when the user types the plugin's [keyword] in
/// the launcher. The manifest only describes *how* to launch it — the live UI is
/// driven entirely by the JSON render frames the script streams back (see
/// `plugin_protocol.dart`).
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.keyword,
    required this.description,
    required this.icon,
    required this.runtime,
    required this.entry,
    required this.args,
    required this.directory,
    this.enabled = true,
  });

  /// Stable identifier — defaults to the containing folder name.
  final String id;

  /// Human-friendly title shown in discovery hints.
  final String name;

  /// The prefix the user types to enter this plugin's live mode, e.g. `weather`.
  final String keyword;

  final String description;

  /// Material icon name (see `plugin_icons.dart`), or `file://` / `https://`.
  final String icon;

  /// Command resolved on PATH: `python`, `node`, `bun`, ...
  final String runtime;

  /// Entry script passed to [runtime], relative to [directory] (e.g. `main.py`).
  final String entry;

  /// Extra argv inserted before [entry].
  final List<String> args;

  /// Absolute path of the plugin's own folder — used as the process working
  /// directory so relative paths inside the script resolve predictably.
  final String directory;

  /// Whether the launcher should surface this plugin. Driven by the optional
  /// `"enabled"` key in `plugin.json` (defaults to `true` when absent) and
  /// toggled from the Launcher Plugins manager. Disabled plugins are still
  /// discovered by the registry so the manager can list them, but they never
  /// match a keyword or appear as a discovery hint.
  final bool enabled;

  bool get isValid => keyword.trim().isNotEmpty && runtime.trim().isNotEmpty && entry.trim().isNotEmpty;

  /// The lowercased keyword used for matching.
  String get keywordLower => keyword.trim().toLowerCase();

  static PluginManifest fromJson(
    Map<String, dynamic> json, {
    required String directory,
    required String folderName,
  }) {
    String str(String key, [String fallback = '']) {
      final Object? value = json[key];
      return value is String ? value : fallback;
    }

    final List<String> args = <String>[];
    final Object? rawArgs = json['args'];
    if (rawArgs is List) {
      for (final Object? arg in rawArgs) {
        if (arg is String) args.add(arg);
      }
    }

    final Object? rawEnabled = json['enabled'];

    return PluginManifest(
      id: str('id', folderName),
      name: str('name', folderName),
      keyword: str('keyword'),
      description: str('description'),
      icon: str('icon', 'extension'),
      runtime: str('runtime'),
      entry: str('entry'),
      args: args,
      directory: directory,
      // Absent or non-boolean `enabled` means the plugin is on by default.
      enabled: rawEnabled is bool ? rawEnabled : true,
    );
  }
}
