import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/color_format_controller.dart'
    show cbrtRoot, sampleFromCmyk, sampleFromHsl, sampleFromOklch, srgbToLinear;
import '../../models/util/color_picker_controller.dart';
import 'windows_scroll.dart';

enum EditorColorSpace { rgb, cmyk, hsl, oklch }

/// A from-scratch color editor: RGB/CMYK/HSL/OKLCH sliders driving a single
/// underlying color, with an apply action. Mirrors the picker panel's
/// color-editor step so it can be reused by other surfaces.
class ColorEditorView extends StatefulWidget {
  const ColorEditorView({
    super.key,
    required this.initial,
    required this.onApply,
    this.onBack,
    this.onChanged,
    this.applyLabel = "Apply & copy",
  });

  final ColorGridSample initial;
  final VoidCallback? onBack;
  final ValueChanged<ColorGridSample> onApply;

  /// Fired live as the user drags any slider, in addition to [onApply].
  final ValueChanged<ColorGridSample>? onChanged;
  final String applyLabel;

  @override
  State<ColorEditorView> createState() => ColorEditorViewState();
}

class ColorEditorViewState extends State<ColorEditorView> {
  EditorColorSpace _space = EditorColorSpace.rgb;

  // Current color stored as linear 0-1 float channels (always updated together)
  late double _r; // 0–255
  late double _g;
  late double _b;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r.toDouble();
    _g = widget.initial.g.toDouble();
    _b = widget.initial.b.toDouble();
  }

  // ── Derived conversions ─────────────────────────────────────────────────

  ColorGridSample get sample {
    final int ri = _r.round().clamp(0, 255);
    final int gi = _g.round().clamp(0, 255);
    final int bi = _b.round().clamp(0, 255);
    final String hex = '${ri.toRadixString(16).padLeft(2, '0')}${gi.toRadixString(16).padLeft(2, '0')}${bi.toRadixString(16).padLeft(2, '0')}';
    return ColorGridSample(r: ri, g: gi, b: bi, hex: hex);
  }

  Color get _color => Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  String get _hexString {
    final int ri = _r.round().clamp(0, 255);
    final int gi = _g.round().clamp(0, 255);
    final int bi = _b.round().clamp(0, 255);
    return '#${ri.toRadixString(16).padLeft(2, '0')}${gi.toRadixString(16).padLeft(2, '0')}${bi.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// Loads a new base color into the editor (e.g. when an external picker
  /// updated the sample while this view stayed open).
  void setSample(ColorGridSample value) {
    setState(() {
      _r = value.r.toDouble();
      _g = value.g.toDouble();
      _b = value.b.toDouble();
    });
  }

  void _update(VoidCallback updater) {
    setState(updater);
    widget.onChanged?.call(sample);
  }

  // HSL
  HSLColor get _hsl => HSLColor.fromColor(_color);

  void _setFromHsl(double h, double s, double l) {
    final ColorGridSample result = sampleFromHsl(h, s, l);
    _update(() {
      _r = result.r.toDouble();
      _g = result.g.toDouble();
      _b = result.b.toDouble();
    });
  }

  // CMYK
  ({double c, double m, double y, double k}) get _cmyk {
    final double rn = _r / 255;
    final double gn = _g / 255;
    final double bn = _b / 255;
    final double maxCh = math.max(rn, math.max(gn, bn));
    final double k = 1 - maxCh;
    if (k >= 0.9999) return (c: 0, m: 0, y: 0, k: 1);
    return (
      c: (1 - rn - k) / (1 - k),
      m: (1 - gn - k) / (1 - k),
      y: (1 - bn - k) / (1 - k),
      k: k,
    );
  }

  void _setFromCmyk(double c, double m, double y, double k) {
    final ColorGridSample result = sampleFromCmyk(c, m, y, k);
    _update(() {
      _r = result.r.toDouble();
      _g = result.g.toDouble();
      _b = result.b.toDouble();
    });
  }

  // OKLCH
  ({double l, double c, double h}) get _oklch {
    final double red = srgbToLinear(_r / 255);
    final double green = srgbToLinear(_g / 255);
    final double blue = srgbToLinear(_b / 255);
    final double lms = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue;
    final double mms = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue;
    final double sms = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue;
    final double lp = cbrtRoot(lms);
    final double mp = cbrtRoot(mms);
    final double sp = cbrtRoot(sms);
    final double L = 0.2104542553 * lp + 0.793617785 * mp - 0.0040720468 * sp;
    final double a = 1.9779984951 * lp - 2.428592205 * mp + 0.4505937099 * sp;
    final double b = 0.0259040371 * lp + 0.7827717662 * mp - 0.808675766 * sp;
    final double chroma = math.sqrt(a * a + b * b);
    double hue = math.atan2(b, a) * 180 / math.pi;
    if (hue < 0) hue += 360;
    return (l: L, c: chroma, h: hue);
  }

  void _setFromOklch(double L, double C, double H) {
    final ColorGridSample result = sampleFromOklch(L, C, H);
    _update(() {
      _r = result.r.toDouble();
      _g = result.g.toDouble();
      _b = result.b.toDouble();
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WindowsScrollView(
      key: const ValueKey<String>('colorEditorView'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Color preview swatch
          _buildEditorSwatch(),
          const SizedBox(height: 10),
          // Space selector tabs
          _buildSpaceTabs(),
          const SizedBox(height: 10),
          // Sliders for active space
          _buildSpaceSliders(),
          const SizedBox(height: 14),
          // Action row
          Row(
            children: <Widget>[
              if (widget.onBack != null) ...<Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 13),
                    label: const Text("Back"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      visualDensity: VisualDensity.compact,
                      textStyle: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => widget.onApply(sample),
                  icon: const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: Color(0xFF11332A),
                  ),
                  label: Text(widget.applyLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    visualDensity: VisualDensity.compact,
                    textStyle: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSwatch() {
    final Color swatch = _color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: swatch.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: swatch.withValues(alpha: 0.32)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: swatch.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _hexString,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              const SizedBox(height: 4),
              Text(
                'rgb(${_r.round()}, ${_g.round()}, ${_b.round()})',
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  color: Design.text.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpaceTabs() {
    return Row(
      children: EditorColorSpace.values.map((EditorColorSpace space) {
        final bool selected = _space == space;
        final String label = switch (space) {
          EditorColorSpace.rgb => 'RGB',
          EditorColorSpace.cmyk => 'CMYK',
          EditorColorSpace.hsl => 'HSL',
          EditorColorSpace.oklch => 'OKLCH',
        };
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _space = space),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: selected ? Design.accent.withValues(alpha: 0.14) : Design.text.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? Design.accent.withValues(alpha: 0.35) : Design.text.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Design.accent : Design.text.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpaceSliders() {
    return switch (_space) {
      EditorColorSpace.rgb => _buildRgbSliders(),
      EditorColorSpace.cmyk => _buildCmykSliders(),
      EditorColorSpace.hsl => _buildHslSliders(),
      EditorColorSpace.oklch => _buildOklchSliders(),
    };
  }

  // ── RGB ─────────────────────────────────────────────────────────────────

  Widget _buildRgbSliders() {
    return Column(
      children: <Widget>[
        _buildColorSlider(
          label: 'R',
          value: _r / 255,
          displayValue: _r.round().toString(),
          unit: '/ 255',
          trackGradient: LinearGradient(
            colors: <Color>[
              Color.fromARGB(255, 0, _g.round(), _b.round()),
              Color.fromARGB(255, 255, _g.round(), _b.round()),
            ],
          ),
          thumbColor: Color.fromARGB(255, _r.round(), 40, 40),
          onChanged: (double v) => _update(() => _r = v * 255),
        ),
        _buildColorSlider(
          label: 'G',
          value: _g / 255,
          displayValue: _g.round().toString(),
          unit: '/ 255',
          trackGradient: LinearGradient(
            colors: <Color>[
              Color.fromARGB(255, _r.round(), 0, _b.round()),
              Color.fromARGB(255, _r.round(), 255, _b.round()),
            ],
          ),
          thumbColor: Color.fromARGB(255, 40, _g.round(), 40),
          onChanged: (double v) => _update(() => _g = v * 255),
        ),
        _buildColorSlider(
          label: 'B',
          value: _b / 255,
          displayValue: _b.round().toString(),
          unit: '/ 255',
          trackGradient: LinearGradient(
            colors: <Color>[
              Color.fromARGB(255, _r.round(), _g.round(), 0),
              Color.fromARGB(255, _r.round(), _g.round(), 255),
            ],
          ),
          thumbColor: Color.fromARGB(255, 40, 40, _b.round()),
          onChanged: (double v) => _update(() => _b = v * 255),
        ),
      ],
    );
  }

  // ── CMYK ────────────────────────────────────────────────────────────────

  Widget _buildCmykSliders() {
    final ({double c, double m, double y, double k}) cmyk = _cmyk;
    return Column(
      children: <Widget>[
        _buildColorSlider(
          label: 'C',
          value: cmyk.c,
          displayValue: '${(cmyk.c * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[_cmykToColor(0, cmyk.m, cmyk.y, cmyk.k), _cmykToColor(1, cmyk.m, cmyk.y, cmyk.k)],
          ),
          thumbColor: const Color(0xFF00AEEF),
          onChanged: (double v) => _setFromCmyk(v, cmyk.m, cmyk.y, cmyk.k),
        ),
        _buildColorSlider(
          label: 'M',
          value: cmyk.m,
          displayValue: '${(cmyk.m * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[_cmykToColor(cmyk.c, 0, cmyk.y, cmyk.k), _cmykToColor(cmyk.c, 1, cmyk.y, cmyk.k)],
          ),
          thumbColor: const Color(0xFFEC008C),
          onChanged: (double v) => _setFromCmyk(cmyk.c, v, cmyk.y, cmyk.k),
        ),
        _buildColorSlider(
          label: 'Y',
          value: cmyk.y,
          displayValue: '${(cmyk.y * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[_cmykToColor(cmyk.c, cmyk.m, 0, cmyk.k), _cmykToColor(cmyk.c, cmyk.m, 1, cmyk.k)],
          ),
          thumbColor: const Color(0xFFFFF200),
          onChanged: (double v) => _setFromCmyk(cmyk.c, cmyk.m, v, cmyk.k),
        ),
        _buildColorSlider(
          label: 'K',
          value: cmyk.k,
          displayValue: '${(cmyk.k * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[_cmykToColor(cmyk.c, cmyk.m, cmyk.y, 0), _cmykToColor(cmyk.c, cmyk.m, cmyk.y, 1)],
          ),
          thumbColor: const Color(0xFF444444),
          onChanged: (double v) => _setFromCmyk(cmyk.c, cmyk.m, cmyk.y, v),
        ),
      ],
    );
  }

  Color _cmykToColor(double c, double m, double y, double k) {
    return Color.fromARGB(
      255,
      ((1 - c) * (1 - k) * 255).round().clamp(0, 255),
      ((1 - m) * (1 - k) * 255).round().clamp(0, 255),
      ((1 - y) * (1 - k) * 255).round().clamp(0, 255),
    );
  }

  // ── HSL ─────────────────────────────────────────────────────────────────

  Widget _buildHslSliders() {
    final HSLColor hsl = _hsl;
    return Column(
      children: <Widget>[
        _buildColorSlider(
          label: 'H',
          value: hsl.hue / 360,
          displayValue: hsl.hue.round().toString(),
          unit: '°',
          trackGradient: const LinearGradient(
            colors: <Color>[
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
          ),
          thumbColor: HSLColor.fromAHSL(1, hsl.hue, 1, 0.5).toColor(),
          onChanged: (double v) => _setFromHsl(v * 360, hsl.saturation, hsl.lightness),
        ),
        _buildColorSlider(
          label: 'S',
          value: hsl.saturation,
          displayValue: '${(hsl.saturation * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[
              HSLColor.fromAHSL(1, hsl.hue, 0, hsl.lightness).toColor(),
              HSLColor.fromAHSL(1, hsl.hue, 1, hsl.lightness).toColor(),
            ],
          ),
          thumbColor: HSLColor.fromAHSL(1, hsl.hue, hsl.saturation, 0.45).toColor(),
          onChanged: (double v) => _setFromHsl(hsl.hue, v, hsl.lightness),
        ),
        _buildColorSlider(
          label: 'L',
          value: hsl.lightness,
          displayValue: '${(hsl.lightness * 100).round()}',
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[
              Colors.black,
              HSLColor.fromAHSL(1, hsl.hue, hsl.saturation, 0.5).toColor(),
              Colors.white,
            ],
          ),
          thumbColor: HSLColor.fromAHSL(1, hsl.hue, hsl.saturation, hsl.lightness).toColor(),
          onChanged: (double v) => _setFromHsl(hsl.hue, hsl.saturation, v),
        ),
      ],
    );
  }

  // ── OKLCH ───────────────────────────────────────────────────────────────

  Widget _buildOklchSliders() {
    final ({double c, double h, double l}) oklch = _oklch;
    return Column(
      children: <Widget>[
        _buildColorSlider(
          label: 'L',
          value: oklch.l.clamp(0.0, 1.0),
          displayValue: (oklch.l * 100).toStringAsFixed(1),
          unit: '%',
          trackGradient: LinearGradient(
            colors: <Color>[
              Colors.black,
              _oklchToColor(0.5, oklch.c, oklch.h),
              Colors.white,
            ],
          ),
          thumbColor: _oklchToColor(oklch.l.clamp(0.0, 1.0), oklch.c, oklch.h),
          onChanged: (double v) => _setFromOklch(v, oklch.c, oklch.h),
        ),
        _buildColorSlider(
          label: 'C',
          value: (oklch.c / 0.4).clamp(0.0, 1.0),
          displayValue: oklch.c.toStringAsFixed(3),
          unit: '',
          trackGradient: LinearGradient(
            colors: <Color>[
              _oklchToColor(oklch.l, 0, oklch.h),
              _oklchToColor(oklch.l, 0.4, oklch.h),
            ],
          ),
          thumbColor: _oklchToColor(oklch.l, oklch.c, oklch.h),
          onChanged: (double v) => _setFromOklch(oklch.l, v * 0.4, oklch.h),
        ),
        _buildColorSlider(
          label: 'H',
          value: oklch.h / 360,
          displayValue: oklch.h.toStringAsFixed(1),
          unit: '°',
          trackGradient: const LinearGradient(
            colors: <Color>[
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
          ),
          thumbColor: _oklchToColor(oklch.l, oklch.c, oklch.h),
          onChanged: (double v) => _setFromOklch(oklch.l, oklch.c, v * 360),
        ),
      ],
    );
  }

  Color _oklchToColor(double L, double C, double H) {
    final double rad = H * math.pi / 180;
    final double a = C * math.cos(rad);
    final double b = C * math.sin(rad);
    final double lp = L + 0.3963377774 * a + 0.2158037573 * b;
    final double mp = L - 0.1055613458 * a - 0.0638541728 * b;
    final double sp = L - 0.0894841775 * a - 1.2914855480 * b;
    final double lms = lp * lp * lp;
    final double mms = mp * mp * mp;
    final double sms = sp * sp * sp;
    final double linR = (4.0767416621 * lms - 3.3077115913 * mms + 0.2309699292 * sms).clamp(0.0, 1.0);
    final double linG = (-1.2684380046 * lms + 2.6097574011 * mms - 0.3413193965 * sms).clamp(0.0, 1.0);
    final double linB = (-0.0041960863 * lms - 0.7034186147 * mms + 1.7076147010 * sms).clamp(0.0, 1.0);
    double toSrgb(double v) {
      if (v <= 0.0031308) return v * 12.92;
      return 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    }

    return Color.fromARGB(
      255,
      (toSrgb(linR) * 255).round().clamp(0, 255),
      (toSrgb(linG) * 255).round().clamp(0, 255),
      (toSrgb(linB) * 255).round().clamp(0, 255),
    );
  }

  // ── Shared slider widget ────────────────────────────────────────────────

  Widget _buildColorSlider({
    required String label,
    required double value,
    required String displayValue,
    required String unit,
    required LinearGradient trackGradient,
    required Color thumbColor,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            child: Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1.5,
                fontWeight: FontWeight.w700,
                color: Design.text.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GradientSlider(
              value: value.clamp(0.0, 1.0),
              gradient: trackGradient,
              thumbColor: thumbColor,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              '$displayValue$unit',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w600,
                color: Design.text.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gradient Slider ───────────────────────────────────────────────────────

class GradientSlider extends StatelessWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.onChanged,
  });

  final double value;
  final LinearGradient gradient;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double thumbRadius = 10.0;
        const double trackHeight = 12.0;
        final double trackWidth = constraints.maxWidth;
        final double thumbX = thumbRadius + value * (trackWidth - thumbRadius * 2);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) {
            final double newVal = ((d.localPosition.dx - thumbRadius) / (trackWidth - thumbRadius * 2)).clamp(0.0, 1.0);
            onChanged(newVal);
          },
          onTapDown: (TapDownDetails d) {
            final double newVal = ((d.localPosition.dx - thumbRadius) / (trackWidth - thumbRadius * 2)).clamp(0.0, 1.0);
            onChanged(newVal);
          },
          child: SizedBox(
            height: thumbRadius * 2 + 4,
            width: trackWidth,
            child: CustomPaint(
              painter: _GradientSliderPainter(
                value: value,
                gradient: gradient,
                thumbColor: thumbColor,
                thumbX: thumbX,
                trackHeight: trackHeight,
                thumbRadius: thumbRadius,
                outlineColor: Design.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GradientSliderPainter extends CustomPainter {
  const _GradientSliderPainter({
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.thumbX,
    required this.trackHeight,
    required this.thumbRadius,
    required this.outlineColor,
  });

  final double value;
  final LinearGradient gradient;
  final Color thumbColor;
  final double thumbX;
  final double trackHeight;
  final double thumbRadius;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    final Rect trackRect = Rect.fromLTWH(0, cy - trackHeight / 2, size.width, trackHeight);
    final RRect trackRRect = RRect.fromRectAndRadius(trackRect, Radius.circular(trackHeight / 2));

    // checker for transparency hint
    final Paint checkerPaint = Paint()..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawRRect(trackRRect, checkerPaint);

    // gradient track
    final Paint gradPaint = Paint()..shader = gradient.createShader(trackRect);
    canvas.drawRRect(trackRRect, gradPaint);

    // track outline
    canvas.drawRRect(
      trackRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = outlineColor.withValues(alpha: 0.18),
    );

    // thumb shadow
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    // thumb fill
    canvas.drawCircle(Offset(thumbX, cy), thumbRadius - 1, Paint()..color = thumbColor);

    // thumb white ring
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbRadius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    // thumb dark ring
    canvas.drawCircle(
      Offset(thumbX, cy),
      thumbRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _GradientSliderPainter old) => old.value != value || old.thumbColor != thumbColor || old.gradient != gradient;
}
