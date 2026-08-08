import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_catalog_service.dart';

/// Discovers XDG application entries and launches them through desktop-entry
/// aware tools before falling back to a safely tokenized Exec command.
class LinuxAppCatalogProvider implements AppCatalogProvider {
  LinuxAppCatalogProvider({List<String>? dataRoots, bool? available})
      : dataRoots = dataRoots ?? _defaultDataRoots(),
        _availableOverride = available;

  final List<String> dataRoots;
  final bool? _availableOverride;

  @override
  bool get isAvailable => _availableOverride ?? Platform.isLinux;

  @override
  String get unavailableReason => isAvailable ? '' : 'The Linux application catalog is unavailable on this platform.';

  @override
  Future<AppCatalogSnapshot> discover() async {
    if (!isAvailable) {
      return AppCatalogSnapshot(records: const <AppCatalogRecord>[], complete: false, error: unavailableReason);
    }

    final Map<String, AppCatalogRecord> records = <String, AppCatalogRecord>{};
    final Set<String> hiddenRecords = <String>{};
    bool complete = true;
    String? error;
    for (final String dataRoot in dataRoots) {
      final String applicationsPath = p.join(dataRoot, 'applications');
      final Directory applications = Directory(applicationsPath);
      if (!applications.existsSync()) continue;
      try {
        await for (final FileSystemEntity entity in applications.list(recursive: true, followLinks: false)) {
          if (entity is! File || p.extension(entity.path).toLowerCase() != '.desktop') continue;
          final _DesktopEntry? entry = _DesktopEntry.parse(entity.path);
          if (entry == null) continue;
          final String desktopId = p.relative(entity.path, from: applications.path).replaceAll('\\', '/');
          final String stableId = 'linux:desktop:$desktopId';
          if (entry.hidden || entry.noDisplay) {
            hiddenRecords.add(stableId);
            records.remove(stableId);
            continue;
          }
          if (hiddenRecords.contains(stableId)) continue;
          final AppCatalogRecord record = AppCatalogRecord(
            stableId: stableId,
            name: entry.name,
            launchTarget: entity.path,
            sourcePath: entity.path,
            subtitle: entry.exec.isEmpty ? desktopId : entry.exec,
            iconPath: _resolveIcon(entry.icon),
            desktopId: desktopId,
            exec: entry.exec,
          );
          // dataRoots are ordered from user-specific to system-wide, so the
          // first entry wins when a desktop ID is overridden.
          records.putIfAbsent(record.stableId, () => record);
        }
      } catch (caught) {
        complete = false;
        error = '$caught';
      }
    }

    final List<AppCatalogRecord> sorted = records.values.toList(growable: false)
      ..sort((AppCatalogRecord a, AppCatalogRecord b) {
        final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName == 0 ? a.stableId.compareTo(b.stableId) : byName;
      });
    return AppCatalogSnapshot(records: sorted, complete: complete, error: error);
  }

  @override
  Future<bool> launch(AppCatalogRecord record) async {
    if (!isAvailable) return false;
    // gio and gtk-launch both honor DBusActivatable entries and the desktop
    // environment's application policy. The Exec fallback is only used when
    // those desktop-entry launchers are not installed or reject the entry.
    if (await _run('gio', <String>['launch', record.sourcePath])) return true;
    final String? desktopId = record.desktopId;
    if (desktopId != null && await _run('gtk-launch', <String>[desktopId])) return true;

    final List<String> command = parseExec(record.exec ?? '');
    if (command.isEmpty) return false;
    try {
      await Process.start(command.first, command.skip(1).toList(growable: false), mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath) async => false;

  Future<bool> _run(String executable, List<String> arguments) async {
    try {
      final ProcessResult result = await Process.run(executable, arguments);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  String? _resolveIcon(String? iconName) {
    final String raw = iconName?.trim() ?? '';
    if (raw.isEmpty) return null;
    final List<String> candidates = <String>[];
    if (p.isAbsolute(raw)) {
      candidates.add(raw);
    } else {
      final String withoutExtension = p.basenameWithoutExtension(raw);
      for (final String root in dataRoots) {
        candidates.addAll(<String>[
          p.join(root, 'pixmaps', raw),
          for (final String size in <String>[
            'scalable',
            '256x256',
            '128x128',
            '64x64',
            '48x48',
            '32x32',
            '24x24',
            '16x16'
          ])
            p.join(root, 'icons', 'hicolor', size, 'apps', raw),
          for (final String extension in <String>['png', 'svg', 'xpm'])
            p.join(root, 'icons', 'hicolor', '48x48', 'apps', '$withoutExtension.$extension'),
        ]);
      }
    }
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static List<String> parseExec(String value) {
    final List<String> tokens = <String>[];
    final StringBuffer token = StringBuffer();
    bool quoted = false;
    String? quote;
    bool escaped = false;

    void flush() {
      if (token.length == 0) return;
      final String cleaned = token.toString();
      if (cleaned.isNotEmpty) tokens.add(cleaned);
      token.clear();
    }

    for (int index = 0; index < value.length; index++) {
      final String character = value[index];
      if (escaped) {
        token.write(character);
        escaped = false;
      } else if (character == '\\' && quote != "'") {
        escaped = true;
      } else if (quoted) {
        if (character == quote) {
          quoted = false;
          quote = null;
        } else {
          token.write(character);
        }
      } else if (character == '"' || character == "'") {
        quoted = true;
        quote = character;
      } else if (character.trim().isEmpty) {
        flush();
      } else {
        token.write(character);
      }
    }
    if (escaped) token.write('\\');
    flush();

    final List<String> result = <String>[];
    for (String item in tokens) {
      item = item.replaceAll('%%', '%');
      item = item.replaceAll(RegExp(r'%[fFuUcCikK]'), '');
      if (item.isNotEmpty) result.add(item);
    }
    return result;
  }

  static List<String> _defaultDataRoots() {
    final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final String? dataHome = Platform.environment['XDG_DATA_HOME'];
    final String dataDirectory =
        dataHome == null || dataHome.trim().isEmpty ? p.join(home, '.local', 'share') : dataHome;
    final String rawDataDirs = Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
    return <String>[
      dataDirectory,
      ...rawDataDirs.split(':').where((String value) => value.trim().isNotEmpty),
    ];
  }
}

class _DesktopEntry {
  const _DesktopEntry({
    required this.name,
    required this.exec,
    this.icon,
    this.hidden = false,
    this.noDisplay = false,
  });

  final String name;
  final String exec;
  final String? icon;
  final bool hidden;
  final bool noDisplay;

  static _DesktopEntry? parse(String path) {
    try {
      final List<String> lines = File(path).readAsLinesSync();
      final Map<String, String> values = <String, String>{};
      bool inDesktopEntry = false;
      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('[')) {
          inDesktopEntry = line == '[Desktop Entry]';
          continue;
        }
        if (!inDesktopEntry) continue;
        final int separator = line.indexOf('=');
        if (separator <= 0) continue;
        values[line.substring(0, separator).trim()] = line.substring(separator + 1).trim();
      }
      if (values['Type'] != 'Application') return null;
      if (!_matchesDesktop(values)) return null;
      final String? name = values['Name'];
      final String? exec = values['Exec'];
      final bool dbusActivatable = _isTrue(values['DBusActivatable']);
      final bool hidden = _isTrue(values['Hidden']);
      final bool noDisplay = _isTrue(values['NoDisplay']);
      if (name == null ||
          name.isEmpty ||
          (!hidden && !noDisplay && (exec == null || exec.isEmpty) && !dbusActivatable)) {
        return null;
      }
      return _DesktopEntry(
        name: name,
        exec: exec ?? '',
        icon: values['Icon'],
        hidden: hidden,
        noDisplay: noDisplay,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isTrue(String? value) => value?.toLowerCase() == 'true';

  static bool _matchesDesktop(Map<String, String> values) {
    final String current = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    final Set<String> desktops =
        current.split(':').map((String value) => value.trim()).where((String value) => value.isNotEmpty).toSet();
    final List<String> onlyShowIn = _desktopList(values['OnlyShowIn']);
    final List<String> notShowIn = _desktopList(values['NotShowIn']);
    if (onlyShowIn.isNotEmpty &&
        desktops.isNotEmpty &&
        desktops.intersection(onlyShowIn.map((String value) => value.toLowerCase()).toSet()).isEmpty) {
      return false;
    }
    if (notShowIn.any((String value) => desktops.contains(value.toLowerCase()))) return false;
    return true;
  }

  static List<String> _desktopList(String? value) {
    return (value ?? '').split(';').map((String item) => item.trim()).where((String item) => item.isNotEmpty).toList();
  }
}
