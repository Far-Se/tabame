Set<String> normalizeFileExtensions(Iterable<String> extensions) {
  return extensions
      .map((String extension) => extension.trim().toLowerCase())
      .where((String extension) => extension.isNotEmpty)
      .map((String extension) => extension.startsWith('.') ? extension : '.$extension')
      .toSet();
}

List<String> parseFileExtensions(String input) {
  return normalizeFileExtensions(input.split(RegExp(r'[\s,;]+'))).toList(growable: false);
}

bool includesFileExtension(
  String fileName,
  Set<String> extensions, {
  required bool excludeMatches,
}) {
  if (extensions.isEmpty) return true;

  final int separatorIndex = fileName.lastIndexOf(RegExp(r'[/\\]'));
  final String basename = separatorIndex == -1 ? fileName : fileName.substring(separatorIndex + 1);
  final int extensionIndex = basename.lastIndexOf('.');
  final String extension = extensionIndex <= 0 ? '' : basename.substring(extensionIndex).toLowerCase();
  final bool matches = extensions.contains(extension);

  return excludeMatches ? !matches : matches;
}
