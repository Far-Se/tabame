part of '../../launcher.dart';

class _LauncherWindowPreviewPanel extends StatefulWidget {
  const _LauncherWindowPreviewPanel({
    super.key,
    required this.window,
    required this.preview,
    required this.onPreviewNeeded,
    required this.design,
    required this.accent,
    required this.onSurface,
  });

  final PlatformWindow window;
  final PlatformWindowPreview? preview;
  final Future<PlatformWindowPreview?> Function() onPreviewNeeded;
  final LauncherDesign design;
  final Color accent;
  final Color onSurface;

  @override
  State<_LauncherWindowPreviewPanel> createState() => _LauncherWindowPreviewPanelState();
}

class _LauncherWindowPreviewPanelState extends State<_LauncherWindowPreviewPanel> {
  Timer? _captureTimer;
  PlatformWindowPreview? _preview;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    if (_preview == null) _scheduleCapture();
  }

  @override
  void didUpdateWidget(covariant _LauncherWindowPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window.identity != widget.window.identity) {
      _preview = widget.preview;
      if (_preview == null) _scheduleCapture();
      return;
    }
    if (widget.preview != null && !identical(oldWidget.preview, widget.preview)) {
      _preview = widget.preview;
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    super.dispose();
  }

  void _scheduleCapture() {
    _captureTimer?.cancel();
    _isLoading = true;
    _captureTimer = Timer(const Duration(milliseconds: 60), () async {
      PlatformWindowPreview? preview;
      try {
        preview = await widget.onPreviewNeeded();
      } catch (_) {
        preview = null;
      }
      if (!mounted) return;
      setState(() {
        _preview = preview ?? _preview;
        _isLoading = false;
      });
    });
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
            child: _preview != null && _preview!.encodedBytes.isNotEmpty
                ? _buildBody(theme, _preview!)
                : _isLoading
                    ? Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: widget.accent.withAlpha(180)),
                        ),
                      )
                    : _buildEmptyPreview(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 7, 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.window_rounded, size: 14, color: widget.accent.withAlpha(210)),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: widget.window.title,
              child: Text(
                widget.window.title,
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

  Widget _buildBody(ThemeData theme, PlatformWindowPreview preview) {
    final String application = widget.window.applicationName.isNotEmpty
        ? widget.window.applicationName
        : widget.window.executable.isNotEmpty
            ? widget.window.executable
            : 'Application';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(35),
                border: Border.all(color: widget.onSurface.withAlpha(18)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.memory(
                  preview.encodedBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                      _buildEmptyPreview(theme),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: widget.onSurface.withAlpha(22)),
        Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
          child: Column(
            children: <Widget>[
              _buildInfoRow(theme, 'APP', application),
              const SizedBox(height: 4),
              _buildInfoRow(theme, 'FRAME', '${preview.width} × ${preview.height}'),
              const SizedBox(height: 4),
              _buildInfoRow(theme, 'STATE', widget.window.isMinimized ? 'Minimized' : 'Open'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPreview(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.hide_image_outlined, size: 30, color: widget.onSurface.withAlpha(80)),
          const SizedBox(height: 7),
          Text(
            WindowWatcherService.instance.isPreviewAvailable ? 'Window preview unavailable' : 'Preview not supported',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: widget.onSurface.withAlpha(115)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
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
}
