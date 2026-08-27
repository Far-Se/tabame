part of '../launcher.dart';

// Constants
// ---------------------------------------------------------------------------

Uint8List? _decodeIcoFileToPng(String path) {
  try {
    final img.Image? decoded = img.decodeImage(File(path).readAsBytesSync());
    return decoded == null ? null : img.encodePng(decoded);
  } catch (_) {
    return null;
  }
}

class _ParsedLauncherTimer {
  const _ParsedLauncherTimer({
    required this.minutes,
    required this.message,
  });

  final int minutes;
  final String message;
}

class _MediaCommandAction {
  const _MediaCommandAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.vk,
    required this.aliases,
  });

  final String id;
  final String label;
  final IconData icon;
  final String vk;
  final List<String> aliases;

  bool matches(String query) => aliases.any((String alias) => alias.startsWith(query));
}

class _LauncherFunctionCommand {
  const _LauncherFunctionCommand({
    required this.name,
    required this.description,
    required this.usage,
    required this.icon,
    this.handler,
    this.streamingHandler,
    this.aliases = const <String>[],
    this.debounce = Duration.zero,
  }) : assert(handler != null || streamingHandler != null, 'A command needs a handler or streamingHandler');

  final String name;
  final String description;
  final String usage;
  final IconData icon;
  final List<String> aliases;
  final Duration debounce;

  /// Standard one-shot handler: computes every result, then returns them all at
  /// once. The framework awaits it and calls `setResults` a single time.
  final FutureOr<List<LauncherSearchResultItem>> Function(String input)? handler;

  /// Streaming handler: takes ownership of the search context and pushes
  /// results incrementally via `context.setResults` as they become available
  /// (e.g. one row per network translation). Preferred over [handler] when set.
  final Future<void> Function(String input, LauncherSearchContext context)? streamingHandler;

  bool matchesName(String value) => value == name || aliases.contains(value);

  bool matchesQuery(String query) {
    final String lower = query.toLowerCase();
    return name.contains(lower) ||
        description.toLowerCase().contains(lower) ||
        usage.toLowerCase().contains(lower) ||
        aliases.any((String alias) => alias.contains(lower));
  }
}

class _ParsedTranslateCommand {
  const _ParsedTranslateCommand({
    required this.text,
    required this.from,
    required this.targets,
  });

  final String text;
  final String from;
  final List<String> targets;
}
