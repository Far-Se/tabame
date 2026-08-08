import 'dart:io';

final RegExp _windowsImport = RegExp(
  r"package:(?:win32|tabamewin32|filepicker_windows|just_audio_windows)/",
);

void main() {
  final Directory lib = Directory('lib');
  final List<String> violations = <String>[];

  for (final FileSystemEntity entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String normalizedPath = entity.path.replaceAll('\\', '/');
    if (normalizedPath.startsWith('lib/platform/windows/')) continue;

    final List<String> lines = entity.readAsLinesSync();
    for (int index = 0; index < lines.length; index++) {
      if (_windowsImport.hasMatch(lines[index])) {
        violations.add('$normalizedPath:${index + 1}: ${lines[index].trim()}');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Windows-only imports must stay inside lib/platform/windows/:');
    stderr.writeAll(violations, '\n');
    exitCode = 1;
    return;
  }

  stdout.writeln('No shared Dart imports of Windows-only packages found.');
}
