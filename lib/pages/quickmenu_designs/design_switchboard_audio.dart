import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quickmenu_modal.dart';
import '../../platform/audio_system_service.dart';
import '../../widgets/itzy/quickmenu/audio_modal.dart';

/// One live output channel. Reads stop while hidden or interacting; queued
/// writes are serialized so rapid drags cannot restore an older volume.
class SwitchboardAudioFader extends StatefulWidget {
  const SwitchboardAudioFader({super.key, required this.vertical});

  final bool vertical;

  @override
  State<SwitchboardAudioFader> createState() => _SwitchboardAudioFaderState();
}

class _SwitchboardAudioFaderState extends State<SwitchboardAudioFader> with QuickMenuTriggers {
  final AudioSystemService _audio = AudioSystemService.instance;
  Timer? _pollTimer;
  bool _reading = false;
  bool _writing = false;
  bool _dragging = false;
  bool _available = false;
  bool _muted = false;
  double _volume = 0;
  double? _pendingVolume;
  bool? _pendingMute;
  int _revision = 0;
  String _device = 'Connecting audio…';
  String? _error;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    unawaited(_initialize());
    _syncPolling();
  }

  Future<void> _initialize() async {
    try {
      await _audio.initialize();
    } catch (_) {
      // The refresh below provides the unavailable state and a retry action.
    }
    if (mounted) await _refresh();
  }

  void _syncPolling() {
    _pollTimer?.cancel();
    if (QuickMenuFunctions.isQuickMenuVisible && Globals.quickMenuPage == QuickMenuPage.quickMenu) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (QuickMenuFunctions.isQuickMenuVisible && Globals.quickMenuPage == QuickMenuPage.quickMenu) {
          unawaited(_refresh());
        }
      });
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    _pollTimer?.cancel();
    if (!visible) _dragging = false;
    if (visible && type == QuickMenuPage.quickMenu) {
      // QuickMenu awaits its listeners before revealing the window. Audio
      // refresh must not delay opening it, especially after a device disconnect.
      unawaited(_refresh());
      _syncPolling();
    }
  }

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {
    if (type != QuickMenuPage.quickMenu) return;
    unawaited(_refresh());
    _syncPolling();
  }

  @override
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) async {
    _pollTimer?.cancel();
    if (newType == QuickMenuPage.quickMenu && visible) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _reading || _writing || _dragging) return;
    _reading = true;
    final int revision = _revision;
    try {
      final PlatformAudioDevice? device =
          _audio.isAvailable ? await _audio.getDefaultDevice(AudioDeviceType.output) : null;
      final double volume = device == null ? 0 : await _audio.getVolume(AudioDeviceType.output);
      final bool muted = device != null && await _audio.getMute(AudioDeviceType.output);
      if (!mounted || revision != _revision || _writing || _dragging) return;
      final String name = device?.name ?? (_audio.isAvailable ? 'No output device' : 'Audio unavailable');
      final double normalized = AudioSystemService.normalizeVolume(volume);
      if (_available == (device != null) && _device == name && _volume == normalized && _muted == muted) return;
      setState(() {
        _available = device != null;
        _device = name;
        _volume = normalized;
        _muted = muted;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() {
          _available = false;
          _device = 'Audio unavailable';
        });
      }
    } finally {
      _reading = false;
    }
  }

  void _changeVolume(double value) {
    if (!_available) return;
    _revision++;
    setState(() {
      _volume = AudioSystemService.normalizeVolume(value);
      _pendingVolume = _volume;
      _error = null;
    });
    unawaited(_flushWrites());
  }

  void _toggleMute() {
    if (!_available) return;
    _revision++;
    setState(() {
      _muted = !_muted;
      _pendingMute = _muted;
      _error = null;
    });
    unawaited(_flushWrites());
  }

  Future<void> _flushWrites() async {
    if (_writing) return;
    _writing = true;
    try {
      while (mounted && (_pendingVolume != null || _pendingMute != null)) {
        final double? volume = _pendingVolume;
        final bool? mute = _pendingMute;
        _pendingVolume = null;
        _pendingMute = null;
        if (volume != null && !await _audio.setVolume(AudioDeviceType.output, volume)) {
          throw StateError('Volume update failed');
        }
        if (mute != null && !await _audio.setMute(AudioDeviceType.output, mute)) {
          throw StateError('Mute update failed');
        }
      }
    } catch (_) {
      _pendingVolume = null;
      _pendingMute = null;
      // if (mounted) setState(() => _error = 'Could not change audio. Try again.');
    } finally {
      _writing = false;
      if (mounted && !_dragging) unawaited(_refresh());
    }
  }

  Future<void> _openAudio() async {
    Globals.audioBoxVisible = true;
    showQuickMenuModal(
      context: context,
      child: const AudioBox(),
      whenComplete: () {
        Globals.audioBoxVisible = false;
        if (mounted) unawaited(_refresh());
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color indicator = _muted ? Design.text.withAlpha(125) : Design.accent;
    final String percentage = _available ? '${(_volume * 100).round()}' : '–';
    final Widget value = Tooltip(
      message: _error ??
          (_available
              ? '$_device · $percentage%${_muted ? ' · muted' : ''} · audio devices'
              : '$_device · click to retry'),
      child: InkWell(
        onTap: _available ? _openAudio : _initialize,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: _error != null
              ? Icon(Icons.error_outline_rounded, size: 19, color: Design.accent)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        percentage,
                        style:
                            TextStyle(color: indicator, fontSize: Design.baseFontSize + 6, fontWeight: FontWeight.w600),
                      ),
                      if (_available)
                        Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: Design.text.withAlpha(175)),
                    ],
                  ),
                ),
        ),
      ),
    );
    final Widget mute = Tooltip(
      message: _available ? (_muted ? 'Unmute output' : 'Mute output') : _device,
      child: Semantics(
        label: 'Mute output',
        toggled: _muted,
        enabled: _available,
        child: InkWell(
          onTap: _available ? _toggleMute : null,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            width: 32,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: _muted ? Design.accent.withAlpha(24) : Colors.transparent,
              border: Border.all(color: _muted ? Design.accent.withAlpha(85) : Design.text.withAlpha(30)),
            ),
            child: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 16,
              color: !_available ? Design.text.withAlpha(90) : (_muted ? Design.accent : Design.text),
            ),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Design.text.withAlpha(6),
        border: widget.vertical
            ? Border(left: BorderSide(color: Design.text.withAlpha(24)))
            : Border(top: BorderSide(color: Design.text.withAlpha(24))),
      ),
      child: widget.vertical
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: <Widget>[
                  Text('OUTPUT',
                      style: TextStyle(
                          fontSize: Design.baseFontSize - 3, letterSpacing: 0.7, color: Design.text.withAlpha(175))),
                  value,
                  Expanded(child: _buildFader(indicator)),
                  const SizedBox(height: 4),
                  mute,
                ],
              ),
            )
          : SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    mute,
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _device,
                      child: Text('OUT',
                          style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(175))),
                    ),
                    Expanded(child: _buildFader(indicator)),
                    SizedBox(width: 54, child: Center(child: value)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFader(Color indicator) {
    Widget slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: indicator,
        inactiveTrackColor: Design.text.withAlpha(35),
        disabledActiveTrackColor: Design.text.withAlpha(25),
        disabledInactiveTrackColor: Design.text.withAlpha(25),
        thumbColor: Design.accent,
        disabledThumbColor: Design.text.withAlpha(80),
        thumbShape: _SwitchboardFaderThumb(ink: Design.background),
        overlayColor: Design.accent.withAlpha(20),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: _volume,
        onChanged: _available ? _changeVolume : null,
        onChangeStart: _available ? (_) => _dragging = true : null,
        onChangeEnd: _available
            ? (_) {
                _dragging = false;
                if (!_writing) unawaited(_refresh());
              }
            : null,
        semanticFormatterCallback: (double value) => '${(value * 100).round()} percent',
      ),
    );
    if (widget.vertical) slider = RotatedBox(quarterTurns: 3, child: slider);

    return Semantics(
      label: 'Output volume',
      child: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (!_available || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _changeVolume(_volume + (event.logicalKey == LogicalKeyboardKey.arrowUp ? 0.02 : -0.02));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy != 0 && _available) {
              GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent _) {
                _changeVolume(_volume + (event.scrollDelta.dy < 0 ? 0.02 : -0.02));
              });
            }
          },
          child: CustomPaint(
            painter: _SwitchboardFaderScale(vertical: widget.vertical, color: Design.text.withAlpha(55)),
            child: slider,
          ),
        ),
      ),
    );
  }
}

class _SwitchboardFaderThumb extends SliderComponentShape {
  const _SwitchboardFaderThumb({required this.ink});

  final Color ink;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 26);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Color fill = Color.lerp(sliderTheme.disabledThumbColor, sliderTheme.thumbColor, enableAnimation.value)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 12, height: 26), const Radius.circular(3)),
      Paint()..color = fill,
    );
    canvas.drawLine(
        center.translate(0, -8),
        center.translate(0, 8),
        Paint()
          ..color = ink
          ..strokeWidth = 1.5);
  }
}

class _SwitchboardFaderScale extends CustomPainter {
  const _SwitchboardFaderScale({required this.vertical, required this.color});

  final bool vertical;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final double length = (vertical ? size.height : size.width) - 28;
    if (length <= 0) return;
    for (int index = 0; index <= 10; index++) {
      final double position = 14 + length * index / 10;
      final double tick = index % 5 == 0 ? 7 : 4;
      if (vertical) {
        canvas.drawLine(Offset(size.width / 2 - 13 - tick, position), Offset(size.width / 2 - 13, position), paint);
        canvas.drawLine(Offset(size.width / 2 + 13, position), Offset(size.width / 2 + 13 + tick, position), paint);
      } else {
        canvas.drawLine(Offset(position, size.height / 2 - 13 - tick), Offset(position, size.height / 2 - 13), paint);
        canvas.drawLine(Offset(position, size.height / 2 + 13), Offset(position, size.height / 2 + 13 + tick), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SwitchboardFaderScale oldDelegate) =>
      vertical != oldDelegate.vertical || color != oldDelegate.color;
}
