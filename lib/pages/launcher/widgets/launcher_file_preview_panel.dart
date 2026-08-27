part of '../../launcher.dart';

class _LauncherFilePreviewData {
  const _LauncherFilePreviewData({
    required this.stat,
    this.text,
    this.textTruncated = false,
    this.icoBytes,
    this.error,
  });

  final FileStat? stat;
  final String? text;
  final bool textTruncated;
  final Uint8List? icoBytes;
  final String? error;
}

class _LauncherFilePreviewPanel extends StatefulWidget {
  const _LauncherFilePreviewPanel({
    super.key,
    required this.entity,
    required this.design,
    required this.accent,
    required this.onSurface,
  });

  final FileSystemEntity entity;
  final LauncherDesign design;
  final Color accent;
  final Color onSurface;

  @override
  State<_LauncherFilePreviewPanel> createState() => _LauncherFilePreviewPanelState();
}

class _LauncherFilePreviewPanelState extends State<_LauncherFilePreviewPanel> {
  static const int _textCharacterLimit = 10000;
  static const int _textReadByteLimit = 64 * 1024;
  static const Set<String> _imageExtensions = <String>{
    '.bmp',
    '.gif',
    '.ico',
    '.jfif',
    '.jpeg',
    '.jpg',
    '.png',
    '.svg',
    '.wbmp',
    '.webp',
  };
  static const Set<String> _markdownExtensions = <String>{'.md', '.markdown'};
  static const Map<String, String> _codeLanguages = <String, String>{
    '.ahk': 'autohotkey',
    '.bash': 'bash',
    '.bat': 'dos',
    '.c': 'c',
    '.cc': 'cpp',
    '.cmd': 'dos',
    '.cpp': 'cpp',
    '.cs': 'csharp',
    '.css': 'css',
    '.dart': 'dart',
    '.env': 'bash',
    '.go': 'go',
    '.gql': 'graphql',
    '.graphql': 'graphql',
    '.h': 'c',
    '.hpp': 'cpp',
    '.htm': 'xml',
    '.html': 'xml',
    '.ini': 'ini',
    '.java': 'java',
    '.js': 'javascript',
    '.json': 'json',
    '.jsonc': 'json',
    '.jsx': 'javascript',
    '.kt': 'kotlin',
    '.kts': 'kotlin',
    '.less': 'less',
    '.lua': 'lua',
    '.m': 'objectivec',
    '.php': 'php',
    '.ps1': 'powershell',
    '.py': 'python',
    '.r': 'r',
    '.rb': 'ruby',
    '.rs': 'rust',
    '.scss': 'scss',
    '.sh': 'bash',
    '.sql': 'sql',
    '.svelte': 'xml',
    '.swift': 'swift',
    '.toml': 'ini',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.vue': 'xml',
    '.xml': 'xml',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.zsh': 'bash',
  };

  late Future<_LauncherFilePreviewData> _previewData;

  @override
  void initState() {
    super.initState();
    _previewData = _loadPreviewData();
  }

  @override
  void didUpdateWidget(covariant _LauncherFilePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.path != widget.entity.path) {
      _previewData = _loadPreviewData();
    }
  }

  String? _decodeTextPreview(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    if (bytes.length >= 2) {
      if (bytes[0] == 0xff && bytes[1] == 0xfe) return _decodeUtf16(bytes, littleEndian: true, offset: 2);
      if (bytes[0] == 0xfe && bytes[1] == 0xff) return _decodeUtf16(bytes, littleEndian: false, offset: 2);
    }

    if (bytes.length >= 4) {
      int evenNulls = 0;
      int oddNulls = 0;
      for (int index = 0; index < bytes.length; index++) {
        if (bytes[index] != 0) continue;
        if (index.isEven) {
          evenNulls++;
        } else {
          oddNulls++;
        }
      }
      final int pairCount = bytes.length ~/ 2;
      if (oddNulls > pairCount * 0.6 && evenNulls < pairCount * 0.1) {
        return _decodeUtf16(bytes, littleEndian: true);
      }
      if (evenNulls > pairCount * 0.6 && oddNulls < pairCount * 0.1) {
        return _decodeUtf16(bytes, littleEndian: false);
      }
    }

    int suspiciousBytes = 0;
    for (final int byte in bytes) {
      if (byte < 0x09 || (byte > 0x0d && byte < 0x20) || byte == 0x7f) suspiciousBytes++;
    }
    if (suspiciousBytes > math.max(2, bytes.length ~/ 100)) return null;

    String decoded = utf8.decode(bytes, allowMalformed: true);
    final int replacementCount = '\u{fffd}'.allMatches(decoded).length;
    if (replacementCount > math.max(2, decoded.length ~/ 50)) {
      decoded = latin1.decode(bytes);
    }
    return decoded.startsWith('\u{feff}') ? decoded.substring(1) : decoded;
  }

  String _decodeUtf16(Uint8List bytes, {required bool littleEndian, int offset = 0}) {
    final List<int> codeUnits = <int>[];
    for (int index = offset; index + 1 < bytes.length; index += 2) {
      codeUnits.add(littleEndian ? bytes[index] | (bytes[index + 1] << 8) : (bytes[index] << 8) | bytes[index + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  Future<_LauncherFilePreviewData> _loadPreviewData() async {
    FileStat? stat;
    try {
      stat = await widget.entity.stat();
    } catch (error) {
      return _LauncherFilePreviewData(stat: null, error: error.toString());
    }

    if (widget.entity is! File) return _LauncherFilePreviewData(stat: stat);

    final String extension = p.extension(widget.entity.path).toLowerCase();
    try {
      if (extension == '.ico') {
        return _LauncherFilePreviewData(
          stat: stat,
          icoBytes: await compute(_decodeIcoFileToPng, widget.entity.path),
        );
      }
      if (!_imageExtensions.contains(extension)) {
        final RandomAccessFile handle = await File(widget.entity.path).open();
        late final Uint8List bytes;
        try {
          bytes = await handle.read(math.min(stat.size, _textReadByteLimit));
        } finally {
          await handle.close();
        }
        final String? decoded = _decodeTextPreview(bytes);
        if (decoded != null) {
          final bool truncated = stat.size > bytes.length || decoded.length > _textCharacterLimit;
          return _LauncherFilePreviewData(
            stat: stat,
            text: decoded.length > _textCharacterLimit ? decoded.substring(0, _textCharacterLimit) : decoded,
            textTruncated: truncated,
          );
        }
      }
    } catch (error) {
      return _LauncherFilePreviewData(stat: stat, error: error.toString());
    }
    return _LauncherFilePreviewData(stat: stat);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double radius = math.min(LauncherThemeData(design: widget.design).frameRadius, 10);
    final Color panelColor = Color.alphaBlend(widget.onSurface.withAlpha(12), theme.colorScheme.surface);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: widget.accent.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(theme),
          Divider(height: 1, thickness: 1, color: widget.onSurface.withAlpha(24)),
          Expanded(
            child: FutureBuilder<_LauncherFilePreviewData>(
              future: _previewData,
              builder: (BuildContext context, AsyncSnapshot<_LauncherFilePreviewData> snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: widget.accent.withAlpha(180)),
                    ),
                  );
                }
                return _buildBody(theme, snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final String name = p.basename(widget.entity.path);
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 7, 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.preview_outlined, size: 14, color: widget.accent.withAlpha(210)),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: widget.entity.path,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.onSurface.withAlpha(220),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: widget.accent.withAlpha(18),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: widget.accent.withAlpha(45)),
            ),
            child: Text(
              'CTRL P',
              style: theme.textTheme.labelSmall?.copyWith(
                color: widget.accent.withAlpha(190),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, _LauncherFilePreviewData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _buildContentPreview(theme, data)),
        Divider(height: 1, thickness: 1, color: widget.onSurface.withAlpha(22)),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildInfoRow(theme, 'TYPE', _fileKind(data.stat)),
              const SizedBox(height: 4),
              _buildInfoRow(theme, 'SIZE', _formatBytes(data.stat?.size)),
              const SizedBox(height: 4),
              _buildInfoRow(theme, 'MODIFIED', _formatDate(data.stat?.modified)),
              const SizedBox(height: 7),
              Tooltip(
                message: widget.entity.path,
                child: Text(
                  widget.entity.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: widget.onSurface.withAlpha(100),
                    fontSize: 8.5,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentPreview(ThemeData theme, _LauncherFilePreviewData data) {
    if (data.error != null) {
      return _buildEmptyPreview(theme, Icons.error_outline_rounded, 'Preview unavailable');
    }
    if (widget.entity is Directory) {
      return _buildEmptyPreview(theme, Icons.folder_rounded, 'Folder');
    }

    final String extension = p.extension(widget.entity.path).toLowerCase();
    if (_imageExtensions.contains(extension)) {
      return Padding(
        padding: const EdgeInsets.all(9),
        child: Center(child: _buildImagePreview(data, extension)),
      );
    }
    if (data.text != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(9),
              child: _buildTextContent(theme, data.text!, extension),
            ),
          ),
          if (data.textTruncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 3, 9, 6),
              child: Text(
                'PREVIEW LIMITED TO 10K CHARACTERS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.accent.withAlpha(165),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      );
    }
    return _buildEmptyPreview(theme, Icons.insert_drive_file_outlined, 'No inline preview');
  }

  Widget _buildTextContent(ThemeData theme, String text, String extension) {
    if (_markdownExtensions.contains(extension)) {
      if (text.trim().isEmpty) return _buildEmptyPreview(theme, Icons.notes_rounded, 'Empty Markdown file');
      return MarkdownBlock(data: text, config: _markdownConfig(theme));
    }

    final String? language = _codeLanguage(text, extension);
    if (language != null) {
      return MarkdownBlock(data: _fencedCode(text, language), config: _markdownConfig(theme));
    }

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: widget.onSurface.withAlpha(190),
        fontFamily: 'Consolas',
        fontFamilyFallback: const <String>['Cascadia Mono', 'Courier New'],
        fontSize: 10,
        height: 1.35,
      ),
    );
  }

  String? _codeLanguage(String text, String extension) {
    final String? mapped = _codeLanguages[extension];
    if (mapped != null) return mapped;

    final String name = p.basename(widget.entity.path).toLowerCase();
    if (name == 'dockerfile') return 'dockerfile';
    if (name == 'makefile') return 'makefile';
    if (!text.startsWith('#!')) return null;
    final String firstLine = text.split('\n').first.toLowerCase();
    if (firstLine.contains('python')) return 'python';
    if (firstLine.contains('node') || firstLine.contains('deno') || firstLine.contains('bun')) return 'javascript';
    if (firstLine.contains('ruby')) return 'ruby';
    if (firstLine.contains('pwsh') || firstLine.contains('powershell')) return 'powershell';
    if (firstLine.contains('bash') || firstLine.contains('/sh')) return 'bash';
    return null;
  }

  String _fencedCode(String text, String language) {
    int longestRun = 0;
    for (final RegExpMatch match in RegExp(r'`+').allMatches(text)) {
      longestRun = math.max(longestRun, match.group(0)!.length);
    }
    final String fence = List<String>.filled(math.max(3, longestRun + 1), '`').join();
    return '$fence$language\n$text\n$fence';
  }

  MarkdownConfig _markdownConfig(ThemeData theme) {
    final Color text = widget.onSurface;
    final Color accent = widget.accent;
    final Color coolTone = Color.lerp(accent, text, 0.35)!;
    final Color warmTone = Color.lerp(accent, const Color(0xFFE3A85B), 0.42)!;
    final Map<String, TextStyle> codeTheme = <String, TextStyle>{
      'root': TextStyle(color: text, backgroundColor: Colors.transparent),
      'comment': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'quote': TextStyle(color: text.withAlpha(105), fontStyle: FontStyle.italic),
      'meta': TextStyle(color: text.withAlpha(155)),
      'keyword': TextStyle(color: accent),
      'selector-tag': TextStyle(color: accent),
      'built_in': TextStyle(color: accent),
      'tag': TextStyle(color: accent),
      'type': TextStyle(color: coolTone),
      'number': TextStyle(color: coolTone),
      'literal': TextStyle(color: coolTone),
      'string': TextStyle(color: warmTone),
      'attr': TextStyle(color: warmTone),
      'title': TextStyle(color: warmTone),
      'section': TextStyle(color: warmTone),
      'function': TextStyle(color: warmTone),
    };

    _LauncherPreviewHeadingConfig heading(MarkdownTag tag, double size) {
      return _LauncherPreviewHeadingConfig(
        tag: tag.name,
        style: (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
          color: text.withAlpha(225),
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      );
    }

    return MarkdownConfig(
      configs: <WidgetConfig>[
        PConfig(
          textStyle: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: text.withAlpha(190),
            fontSize: 10,
            height: 1.4,
          ),
        ),
        heading(MarkdownTag.h1, 15),
        heading(MarkdownTag.h2, 13.5),
        heading(MarkdownTag.h3, 12),
        heading(MarkdownTag.h4, 11),
        heading(MarkdownTag.h5, 10.5),
        heading(MarkdownTag.h6, 10),
        HrConfig(height: 1, color: text.withAlpha(28)),
        CodeConfig(
          style: TextStyle(
            color: accent,
            backgroundColor: accent.withAlpha(24),
            fontFamily: 'Consolas',
            fontSize: 9.5,
          ),
        ),
        PreConfig(
          textStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 9.5, height: 1.4),
          styleNotMatched: TextStyle(color: text.withAlpha(205)),
          theme: codeTheme,
          decoration: BoxDecoration(
            color: text.withAlpha(10),
            border: Border.all(color: accent.withAlpha(38)),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(7),
        ),
        BlockquoteConfig(
          sideColor: accent.withAlpha(120),
          sideWith: 1,
          textColor: text.withAlpha(180),
          padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
        ),
        LinkConfig(
          style: TextStyle(
            color: accent,
            fontSize: 10,
            decoration: TextDecoration.underline,
            decorationColor: accent.withAlpha(130),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(_LauncherFilePreviewData data, String extension) {
    Widget errorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
      return _buildEmptyPreview(Theme.of(context), Icons.broken_image_outlined, 'Preview unavailable');
    }

    if (extension == '.svg') {
      return SvgPicture.file(
        File(widget.entity.path),
        fit: BoxFit.scaleDown,
        errorBuilder: (BuildContext context, Object error, StackTrace stackTrace) =>
            errorBuilder(context, error, stackTrace),
      );
    }
    if (extension == '.ico') {
      final Uint8List? bytes = data.icoBytes;
      if (bytes == null) {
        return _buildEmptyPreview(Theme.of(context), Icons.broken_image_outlined, 'Preview unavailable');
      }
      return Image.memory(
        bytes,
        fit: BoxFit.scaleDown,
        filterQuality: FilterQuality.medium,
        errorBuilder: errorBuilder,
      );
    }
    return Image.file(
      File(widget.entity.path),
      fit: BoxFit.scaleDown,
      filterQuality: FilterQuality.medium,
      errorBuilder: errorBuilder,
    );
  }

  Widget _buildEmptyPreview(ThemeData theme, IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 30, color: widget.onSurface.withAlpha(80)),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: widget.onSurface.withAlpha(115)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: widget.onSurface.withAlpha(85),
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: widget.onSurface.withAlpha(180),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _fileKind(FileStat? stat) {
    if (stat == null || stat.type == FileSystemEntityType.notFound) return 'Unavailable';
    if (stat.type == FileSystemEntityType.directory) return 'Folder';
    if (stat.type == FileSystemEntityType.link) return 'Shortcut / link';
    final String extension = p.extension(widget.entity.path);
    return extension.isEmpty ? 'File' : '${extension.substring(1).toUpperCase()} file';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || widget.entity is Directory) return '—';
    if (bytes < 1024) return '$bytes B';
    const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final DateTime local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _LauncherPreviewHeadingConfig extends HeadingConfig {
  const _LauncherPreviewHeadingConfig({
    required this.tag,
    required this.style,
  });

  @override
  final String tag;
  @override
  final TextStyle style;
  @override
  EdgeInsets get padding => const EdgeInsets.only(top: 8, bottom: 3);
  @override
  HeadingDivider? get divider => null;
}
