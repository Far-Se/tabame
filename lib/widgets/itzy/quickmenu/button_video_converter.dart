import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/util/video_converter.dart';
import '../../../models/win32/win_utils.dart';
import '../../../platform/file_picker_service.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class VideoConverterButton extends StatelessWidget {
  const VideoConverterButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: 'FFmpeg Video Converter',
      icon: const Icon(Icons.video_settings_rounded),
      onTap: () => showQuickMenuModal(context: context, child: const VideoConverterPanel()),
    );
  }
}

void _openConvertedFile(String path) {
  if (!Platform.isWindows) {
    //TODO: Implement multiplatform
    return;
  }
  WinUtils.open(path, parseParamaters: false);
  QuickMenuFunctions.hideQuickMenu();
}

class VideoConverterPanel extends StatefulWidget {
  const VideoConverterPanel({super.key});

  @override
  State<VideoConverterPanel> createState() => _VideoConverterPanelState();
}

class _VideoConverterPanelState extends State<VideoConverterPanel> {
  static const String _settingsKey = 'videoConverter.options';
  static const List<String> _editFields = <String>[
    'trim_start',
    'trim_end',
    'crop_left',
    'crop_top',
    'crop_right',
    'crop_bottom',
  ];
  final VideoConverter _converter = VideoConverter.instance;
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  late final VideoConversionOptions _options;
  Future<void> _saveQueue = Future<void>.value();
  bool _advanced = false;
  bool _picking = false;
  bool _confirmDelete = false;
  bool _deleting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic>? saved;
    try {
      final dynamic decoded = jsonDecode(Boxes.pref.getString(_settingsKey) ?? '{}');
      if (decoded is Map<String, dynamic>) saved = decoded;
    } catch (_) {
      _message = 'Saved options could not be read. Defaults restored.';
    }
    _options = VideoConversionOptions(saved);
    for (final String key in <String>['input', 'output_dir', 'output_name', ..._editFields]) {
      _controllers[key] = TextEditingController(text: _options.text(key));
    }
    _converter.addListener(_onJobChanged);
    if (_converter.available) _syncPreset();
    if (!_converter.available && !_converter.busy) unawaited(_converter.detectTools());
  }

  void _syncPreset() {
    final List<VideoConversionPreset> presets = _converter.presets;
    if (_converter.available && !presets.any((VideoConversionPreset item) => item.id == _options.text('preset'))) {
      _options.values['preset'] = presets.first.id;
      _persist();
    }
  }

  void _onJobChanged() {
    if (!mounted) return;
    _syncPreset();
    setState(() {});
  }

  void _persist() {
    final String snapshot = jsonEncode(_options.values);
    _saveQueue = _saveQueue.then((_) => Boxes.updateSettings(_settingsKey, snapshot)).catchError((Object error) {
      if (mounted) setState(() => _message = 'Could not save options: $error');
    });
  }

  void _change(String key, dynamic value) {
    setState(() {
      _options.values[key] = value;
      _message = null;
    });
    _persist();
  }

  @override
  void dispose() {
    _converter.removeListener(_onJobChanged);
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick({required bool folder}) async {
    if (_picking) return;
    if (!FilePickerService.instance.isAvailable) {
      setState(() => _message = FilePickerService.instance.unavailableReason);
      return;
    }
    setState(() => _picking = true);
    final bool wasKeptOpen = QuickMenuFunctions.keepOpen;
    QuickMenuFunctions.keepOpen = true;
    try {
      String? selected;
      if (folder) {
        selected = (await (DirectoryPicker()..title = 'Choose output folder').getDirectoryAsync())?.path;
      } else {
        selected = (await (OpenFilePicker()
                  ..title = 'Choose input media'
                  ..filterSpecification = <String, String>{
                    'Media files':
                        '*.mp4;*.mkv;*.mov;*.webm;*.avi;*.wmv;*.m4v;*.mpg;*.mpeg;*.ts;*.flv;*.mp3;*.m4a;*.wav;*.flac;*.ogg;*.gif',
                    'All files': '*.*',
                  })
                .getFileAsync())
            ?.path;
      }
      if (!mounted || selected == null) return;
      final String key = folder ? 'output_dir' : 'input';
      _controllers[key]!.text = selected;
      _change(key, selected);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not open file picker: $error');
    } finally {
      QuickMenuFunctions.keepOpen = wasKeptOpen;
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) setState(() => _message = 'Copied to clipboard.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not copy: $error');
    }
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await _converter.deleteOutput();
      if (mounted) setState(() => _confirmDelete = false);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not delete output: $error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _start() {
    FocusScope.of(context).unfocus();
    try {
      VideoConversionEdits.fromOptions(_options);
    } on FormatException catch (error) {
      setState(() => _message = error.message);
      return;
    }
    setState(() {
      _message = null;
      _confirmDelete = false;
    });
    unawaited(_converter.convert(_options, onOpen: _openConvertedFile));
  }

  void _resetEdits() {
    setState(() {
      for (final String key in <String>['trim_enabled', 'crop_enabled', ..._editFields]) {
        _options.values[key] = VideoConversionOptions.defaults[key];
        if (_controllers.containsKey(key)) _controllers[key]!.text = _options.text(key);
      }
      _message = null;
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final bool idle = _converter.status == VideoConversionStatus.idle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: 'Video Converter',
          icon: Icons.video_settings_rounded,
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: 'Check FFmpeg encoders again',
          buttonPressed: _converter.busy || _converter.detecting ? null : () => unawaited(_converter.detectTools()),
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              children: <Widget>[
                if (_message != null) ...<Widget>[_notice(_message!), const SizedBox(height: 8)],
                if (idle) ..._form() else _job(),
              ],
            ),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  List<Widget> _form() {
    final VideoConversionPreset preset = _options.preset;
    return <Widget>[
      if (_converter.detecting)
        _card('FFmpeg', Icons.settings_ethernet_rounded, <Widget>[
          LinearProgressIndicator(minHeight: 2, color: Design.accent, backgroundColor: Design.text.withAlpha(15)),
          const SizedBox(height: 8),
          _text('Checking available encoders…', muted: true),
        ])
      else if (!_converter.available)
        _card('FFmpeg unavailable', Icons.info_outline_rounded, <Widget>[
          _text(_converter.toolError ?? 'FFmpeg is required to convert media.'),
          const SizedBox(height: 8),
          _action('Check again', Icons.refresh_rounded, () => unawaited(_converter.detectTools())),
        ])
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(children: <Widget>[
            Icon(Icons.check_circle_outline_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 6),
            Expanded(child: _text('FFmpeg ready', muted: true)),
            _badge('${_converter.presets.length} presets'),
          ]),
        ),
      _card('Files', Icons.folder_open_rounded, <Widget>[
        if (_options.text('input').isEmpty) ...<Widget>[
          _text('Choose media to compress, convert, or extract audio.', muted: true),
          const SizedBox(height: 8),
        ],
        _field('input', 'Input media', 'Choose a file or paste its path',
            browse: () => unawaited(_pick(folder: false))),
        const SizedBox(height: 8),
        _field('output_dir', 'Output folder', 'Same folder as input', browse: () => unawaited(_pick(folder: true))),
        const SizedBox(height: 8),
        _field('output_name', 'Output name', 'Automatic name · ${preset.extension}'),
      ]),
      const SizedBox(height: 8),
      _card('Encoding', Icons.tune_rounded, <Widget>[
        _select('preset', 'Format / codec', <String, String>{
          for (final VideoConversionPreset item
              in (_converter.available ? _converter.presets : <VideoConversionPreset>[preset]))
            item.id: item.label,
        }),
        if (preset.isVideo || preset.isGif) ...<Widget>[
          const SizedBox(height: 8),
          _select('quality', 'Quality / size', VideoConversionOptions.choices['quality']!),
        ],
        if (preset.isVideo) ...<Widget>[
          const SizedBox(height: 8),
          _select('speed', 'Encoding speed', VideoConversionOptions.choices['speed']!),
        ],
        if (preset.isCopy) _text('Copies all streams without re-encoding.', muted: true),
        if (preset.id.endsWith('nvenc') || preset.id.endsWith('qsv') || preset.id.endsWith('amf'))
          _text('Requires a compatible GPU and driver.', muted: true),
      ]),
      const SizedBox(height: 8),
      _card('Trim & crop', Icons.content_cut_rounded, <Widget>[
        _toggle('trim_enabled', 'Trim media'),
        if (_options.flag('trim_enabled')) ...<Widget>[
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(child: _field('trim_start', 'Start time', '0:00')),
            const SizedBox(width: 8),
            Expanded(child: _field('trim_end', 'End time', 'End of media')),
          ]),
          const SizedBox(height: 6),
          _text('Use seconds, MM:SS, or HH:MM:SS. Decimals are accepted. End time is measured from the original start.',
              muted: true),
          if (preset.isCopy) ...<Widget>[
            const SizedBox(height: 6),
            _notice('MKV remux cuts at nearby keyframes. Choose a video encoding preset for precise trimming.'),
          ],
          const SizedBox(height: 8),
        ],
        if (preset.isVideo || preset.isGif) ...<Widget>[
          _toggle('crop_enabled', 'Crop video edges'),
          if (_options.flag('crop_enabled')) ...<Widget>[
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(child: _field('crop_left', 'Left (px)', '0', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('crop_right', 'Right (px)', '0', keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(child: _field('crop_top', 'Top (px)', '0', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field('crop_bottom', 'Bottom (px)', '0', keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 6),
            _text('Pixels to remove from each edge of the displayed video, before resizing. Requires ffprobe.',
                muted: true),
            if (preset.isVideo) _text('Leave an even width and height for video encoding.', muted: true),
          ],
        ] else
          _text(
              preset.isCopy
                  ? 'Cropping requires a video encoding or GIF preset.'
                  : 'Cropping is inactive for audio extraction.',
              muted: true),
        if (_options.flag('trim_enabled') || _options.flag('crop_enabled')) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: _action('Reset edits', Icons.restart_alt_rounded, _resetEdits)),
        ],
      ]),
      const SizedBox(height: 8),
      _action(
          _advanced ? 'Hide advanced options' : 'Advanced options',
          _advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          () => setState(() => _advanced = !_advanced)),
      if (_advanced) ...<Widget>[
        const SizedBox(height: 8),
        _card('Output controls', Icons.settings_outlined, <Widget>[
          if (preset.isVideo || preset.isGif) ...<Widget>[
            _select('resolution', 'Maximum height', VideoConversionOptions.choices['resolution']!),
            const SizedBox(height: 8),
            _select('fps', 'Maximum frame rate', VideoConversionOptions.choices['fps']!),
            const SizedBox(height: 4),
            _text('Smaller sources are never upscaled. GIF defaults to a 15 fps cap.', muted: true),
            const SizedBox(height: 8),
          ],
          if (preset.isVideo || preset.isAudio) ...<Widget>[
            _select('audio_bitrate', 'Audio bitrate', VideoConversionOptions.choices['audio_bitrate']!),
            const SizedBox(height: 8),
          ],
          if (preset.isVideo) _toggle('remove_audio', 'Remove audio'),
          _toggle('overwrite', 'Replace existing output'),
          _text('Otherwise, a numbered filename is created.', muted: true),
          _toggle('open_when_done', 'Open output when finished'),
        ]),
      ],
    ];
  }

  Widget _job() {
    final VideoConversionStatus status = _converter.status;
    final bool complete = status == VideoConversionStatus.complete;
    final String title = switch (status) {
      VideoConversionStatus.idle => 'Ready',
      VideoConversionStatus.preparing => 'Inspecting media',
      VideoConversionStatus.converting => _converter.cancelling ? 'Cancelling…' : 'Converting',
      VideoConversionStatus.complete => 'Conversion complete',
      VideoConversionStatus.cancelled => 'Conversion cancelled',
      VideoConversionStatus.failed => 'Conversion failed',
    };
    final double delta = _converter.sourceBytes > 0 ? (1 - _converter.outputBytes / _converter.sourceBytes) * 100 : 0;
    return _card(title, complete ? Icons.check_circle_outline_rounded : Icons.movie_outlined, <Widget>[
      _text(p.basename(_converter.inputPath)),
      const SizedBox(height: 4),
      _text(_converter.presetLabel, muted: true),
      const SizedBox(height: 12),
      if (_converter.busy) ...<Widget>[
        LinearProgressIndicator(
            value: _converter.progress, minHeight: 3, color: Design.accent, backgroundColor: Design.text.withAlpha(15)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          _badge(_converter.progress == null ? 'Working' : '${(_converter.progress! * 100).toStringAsFixed(0)}%'),
          _badge(VideoConverter.formatDuration(_converter.elapsed)),
          _badge(_converter.speed),
          _badge(VideoConverter.formatBytes(_converter.outputBytes)),
        ]),
        const SizedBox(height: 10),
        _text('You can close this panel and return to the same job while Tabame is running.', muted: true),
      ] else ...<Widget>[
        _metric('Elapsed', VideoConverter.formatDuration(_converter.elapsed)),
        if (_converter.duration != null)
          _metric('Selected duration', VideoConverter.formatDuration(Duration(seconds: _converter.duration!.round()))),
        _metric('Input size', VideoConverter.formatBytes(_converter.sourceBytes)),
        if (complete) ...<Widget>[
          _metric('Output size', VideoConverter.formatBytes(_converter.outputBytes)),
          if (_converter.sourceBytes > 0)
            _metric('Size change', '${delta.abs().toStringAsFixed(1)}% ${delta >= 0 ? 'smaller' : 'larger'}'),
          const SizedBox(height: 8),
          SelectableText(_converter.outputPath!, style: TextStyle(color: Design.text, fontSize: Design.baseFontSize)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            _action('Open file', Icons.open_in_new_rounded, () => _openConvertedFile(_converter.outputPath!)),
            _action('Folder', Icons.folder_open_rounded, () => _openConvertedFile(p.dirname(_converter.outputPath!))),
            _action('Copy path', Icons.copy_rounded, () => unawaited(_copy(_converter.outputPath!))),
            _action('Delete', Icons.delete_outline_rounded, () => setState(() => _confirmDelete = !_confirmDelete)),
          ]),
          if (_confirmDelete) ...<Widget>[
            const SizedBox(height: 10),
            _text('Permanently delete the converted file?'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              _action('Delete output', Icons.delete_outline_rounded, _deleting ? null : () => unawaited(_delete())),
              _action(
                  'Keep file', Icons.close_rounded, _deleting ? null : () => setState(() => _confirmDelete = false)),
            ]),
          ],
        ],
        if (status == VideoConversionStatus.cancelled)
          _text('The conversion was stopped. Existing files were preserved.', muted: true),
        if (_converter.error != null) ...<Widget>[const SizedBox(height: 8), _notice(_converter.error!)],
        if (_converter.diagnostics.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: _text('FFmpeg diagnostics'),
            children: <Widget>[
              SelectableText(_converter.diagnostics,
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(190))),
              const SizedBox(height: 6),
              _action('Copy diagnostics', Icons.copy_rounded,
                  () => unawaited(_copy('${_converter.error ?? ''}\n${_converter.diagnostics}'))),
            ],
          ),
        ],
      ],
      if (_converter.probeWarning != null) ...<Widget>[const SizedBox(height: 8), _notice(_converter.probeWarning!)],
    ]);
  }

  Widget _bottomBar() {
    final bool idle = _converter.status == VideoConversionStatus.idle;
    final String label = _converter.busy
        ? (_converter.cancelling ? 'Cancelling…' : 'Cancel conversion')
        : idle
            ? 'Start conversion'
            : 'Back to converter';
    final VoidCallback? action = _converter.busy
        ? (_converter.canCancel ? _converter.cancel : null)
        : idle
            ? (_converter.available && !_converter.detecting && !_picking && _options.text('input').trim().isNotEmpty
                ? _start
                : null)
            : (_deleting
                ? null
                : () {
                    setState(() {
                      _message = null;
                      _confirmDelete = false;
                    });
                    _converter.reset();
                  });
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(15)))),
        child: _action(
            label,
            _converter.busy
                ? Icons.stop_rounded
                : idle
                    ? Icons.play_arrow_rounded
                    : Icons.arrow_back_rounded,
            action,
            primary: true),
      ),
    );
  }

  Widget _text(String text, {bool muted = false}) => Text(text,
      style: TextStyle(
        fontSize: Design.baseFontSize + (muted ? 0 : 1),
        color: muted ? Design.text.withAlpha(165) : Design.text,
      ));

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Design.accent.withAlpha(18), borderRadius: BorderRadius.circular(99)),
        child: Text(text,
            style: TextStyle(color: Design.accent, fontSize: Design.baseFontSize, fontWeight: FontWeight.w700)),
      );

  Widget _card(String title, IconData icon, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
            color: Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Design.text.withAlpha(16))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Icon(icon, size: 14, color: Design.accent),
            const SizedBox(width: 6),
            Expanded(
                child: Text(title.toUpperCase(),
                    style: TextStyle(
                        color: Design.text,
                        fontSize: Design.baseFontSize + 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _notice(String text) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Design.accent.withAlpha(10),
            border: Border(left: BorderSide(color: Design.accent.withAlpha(80), width: 2))),
        child: _text(text),
      );

  Widget _metric(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Expanded(child: _text(label, muted: true)),
          const SizedBox(width: 8),
          Flexible(child: _text(value)),
        ]),
      );

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: Design.text.withAlpha(7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        labelStyle: TextStyle(color: Design.text.withAlpha(180), fontSize: Design.baseFontSize),
        hintStyle: TextStyle(color: Design.text.withAlpha(110), fontSize: Design.baseFontSize),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(24))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.accent.withAlpha(90))),
      );

  Widget _field(String key, String label, String hint, {VoidCallback? browse, TextInputType? keyboardType}) =>
      TextField(
        controller: _controllers[key],
        keyboardType: keyboardType,
        style: TextStyle(color: Design.text, fontSize: Design.baseFontSize + 1),
        decoration: _decoration(label,
            hint: hint,
            suffix: browse == null
                ? null
                : IconButton(
                    tooltip: 'Browse',
                    onPressed: _picking ? null : browse,
                    icon: Icon(Icons.folder_open_rounded, size: 17, color: Design.accent),
                  )),
        onChanged: (String value) => _change(key, value),
      );

  Widget _select(String key, String label, Map<String, String> choices) => InputDecorator(
        decoration: _decoration(label),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          value: _options.text(key),
          isExpanded: true,
          isDense: true,
          style: TextStyle(color: Design.text, fontSize: Design.baseFontSize + 1),
          items: choices.entries
              .map((MapEntry<String, String> item) => DropdownMenuItem<String>(
                    value: item.key,
                    child: Text(item.value, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (String? value) {
            if (value != null) _change(key, value);
          },
        )),
      );

  Widget _toggle(String key, String label) => InkWell(
        onTap: () => _change(key, !_options.flag(key)),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Design.accent.withAlpha(14),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: <Widget>[
              Expanded(child: _text(label)),
              const SizedBox(width: 8),
              MiniToggleSwitch(value: _options.flag(key), onChanged: (bool value) => _change(key, value)),
            ])),
      );

  Widget _action(String label, IconData icon, VoidCallback? onTap, {bool primary = false}) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, textAlign: TextAlign.center),
        style: TextButton.styleFrom(
          foregroundColor: Design.accent,
          disabledForegroundColor: Design.text.withAlpha(85),
          backgroundColor: Design.accent.withAlpha(primary ? 24 : 10),
          padding: EdgeInsets.symmetric(horizontal: primary ? 18 : 10, vertical: primary ? 12 : 8),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: TextStyle(
              fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, letterSpacing: primary ? 0.4 : 0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Design.accent.withAlpha(primary ? 80 : 25))),
        ),
      );
}
