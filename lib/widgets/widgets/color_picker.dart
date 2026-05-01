import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/settings.dart';

class CustomColorPicker extends StatefulWidget {
  const CustomColorPicker({
    super.key,
    required this.startColor,
    required this.themeOptions,
    required this.colorIndex,
    required this.onColorChanged,
  });
  final Color startColor;
  final List<List<int>> themeOptions;
  final int colorIndex;
  final Function(Color) onColorChanged;

  @override
  State<CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<CustomColorPicker> {
  late Color currentColor;
  late TextEditingController rController;
  late TextEditingController gController;
  late TextEditingController bController;
  late TextEditingController hexController;

  // OKLCH State
  bool _useOklch = false;
  late TextEditingController lController;
  late TextEditingController cController;
  late TextEditingController hController;

  @override
  void initState() {
    super.initState();
    currentColor = widget.startColor;
    rController = TextEditingController(text: currentColor.red8bit.toString());
    gController = TextEditingController(text: currentColor.green8bit.toString());
    bController = TextEditingController(text: currentColor.blue8bit.toString());
    hexController = TextEditingController(text: _colorToHex(currentColor));

    final _OKLCH oklch = _rgbToOklch(currentColor);
    lController = TextEditingController(text: (oklch.l * 100).toStringAsFixed(1));
    cController = TextEditingController(text: oklch.c.toStringAsFixed(3));
    hController = TextEditingController(text: oklch.h.toStringAsFixed(1));
  }

  @override
  void dispose() {
    rController.dispose();
    gController.dispose();
    bController.dispose();
    hexController.dispose();
    lController.dispose();
    cController.dispose();
    hController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return color.value32bit.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
  }

  void _updateHexFromColor() {
    final String hex = _colorToHex(currentColor);
    if (hexController.text.toUpperCase() != hex) {
      hexController.text = hex;
    }
  }

  void _updateColorFromHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      final int? val = int.tryParse(hex, radix: 16);
      if (val != null) {
        setState(() {
          currentColor = Color(0xFF000000 | val);
          _syncRgbControllers();
          widget.onColorChanged(currentColor);
        });
      }
    }
  }

  void _syncRgbControllers() {
    rController.text = currentColor.red8bit.toString();
    gController.text = currentColor.green8bit.toString();
    bController.text = currentColor.blue8bit.toString();
    _syncOklchFromCurrent();
  }

  void _syncOklchFromCurrent() {
    final _OKLCH oklch = _rgbToOklch(currentColor);
    lController.text = (oklch.l * 100).toStringAsFixed(1);
    cController.text = oklch.c.toStringAsFixed(3);
    hController.text = oklch.h.toStringAsFixed(1);
  }

  void _syncRgbFromCurrent() {
    rController.text = currentColor.red8bit.toString();
    gController.text = currentColor.green8bit.toString();
    bController.text = currentColor.blue8bit.toString();
  }

  // --- OKLCH Math ---

  double _srgbToLinear(double v) {
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  double _linearToSrgb(double v) {
    if (v.isNaN || v.isInfinite) return 0;
    if (v < 0) return 0;
    return v <= 0.0031308 ? v * 12.92 : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
  }

  /// Cube root that correctly handles negative numbers.
  double _cbrt(double v) {
    if (v == 0) return 0;
    if (v < 0) return -math.pow(-v, 1 / 3).toDouble();
    return math.pow(v, 1 / 3).toDouble();
  }

  _OKLCH _rgbToOklch(Color color) {
    final double r = _srgbToLinear(color.red8bit / 255.0);
    final double g = _srgbToLinear(color.green8bit / 255.0);
    final double b = _srgbToLinear(color.blue8bit / 255.0);

    final double lmsL = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final double lmsM = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final double lmsS = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    final double l_ = _cbrt(lmsL);
    final double m_ = _cbrt(lmsM);
    final double s_ = _cbrt(lmsS);

    final double L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720403 * s_;
    final double a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    final double b_ = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    final double C = math.sqrt(a * a + b_ * b_);
    double H = math.atan2(b_, a) * 180 / math.pi;
    if (H < 0) H += 360;

    return _OKLCH(L.clamp(0.0, 1.0), C.clamp(0.0, 0.5), H);
  }

  Color _oklchToRgb(double L, double C, double H) {
    final double a = C * math.cos(H * math.pi / 180);
    final double b = C * math.sin(H * math.pi / 180);

    final double l_ = L + 0.3963377774 * a + 0.2158037573 * b;
    final double m_ = L - 0.1055613458 * a - 0.0638541728 * b;
    final double s_ = L - 0.0894841775 * a - 1.2914855480 * b;

    final double lmsL = l_ * l_ * l_;
    final double lmsM = m_ * m_ * m_;
    final double lmsS = s_ * s_ * s_;

    final double rL = 4.0767416621 * lmsL - 3.3077115913 * lmsM + 0.2309699292 * lmsS;
    final double gL = -1.2684380046 * lmsL + 2.6097574011 * lmsM - 0.3413193965 * lmsS;
    final double bL = -0.0041960863 * lmsL - 0.7034186147 * lmsM + 1.7068272365 * lmsS;

    final int cr = (_linearToSrgb(rL) * 255).round().clamp(0, 255);
    final int cg = (_linearToSrgb(gL) * 255).round().clamp(0, 255);
    final int cb = (_linearToSrgb(bL) * 255).round().clamp(0, 255);

    return Color.fromARGB(255, cr, cg, cb);
  }

  @override
  Widget build(BuildContext context) {
    final Set<Color> predefinedColors = <Color>{};
    for (List<int> list in widget.themeOptions) {
      if (widget.colorIndex >= 0 && widget.colorIndex < list.length) {
        predefinedColors.add(Color(list[widget.colorIndex]).withAlpha(255));
      }
    }
    final List<Color> colorsList = predefinedColors.toList();
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    // Sync controllers if currentColor changed from sliders
    if (int.tryParse(rController.text) != currentColor.red8bit) {
      rController.text = currentColor.red8bit.toString();
    }
    if (int.tryParse(gController.text) != currentColor.green8bit) {
      gController.text = currentColor.green8bit.toString();
    }
    if (int.tryParse(bController.text) != currentColor.blue8bit) {
      bController.text = currentColor.blue8bit.toString();
    }
    _updateHexFromColor();

    return SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Row(children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: currentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: onSurface.withValues(alpha: 0.2)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: currentColor.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: hexController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    decoration: InputDecoration(
                      prefixText: "#",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      filled: true,
                      fillColor: onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: _updateColorFromHex,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 90,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: <Widget>[
                      _buildModeButton("RGB", !_useOklch, () => setState(() => _useOklch = false), onSurface),
                      _buildModeButton("OKLCH", _useOklch, () => setState(() => _useOklch = true), onSurface),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
                child: _useOklch
                    ? Column(children: <Widget>[
                        _buildSlider(currentColorToOklch.l * 100, Colors.grey, lController, (double v) {
                          setState(() {
                            final _OKLCH current = _rgbToOklch(currentColor);
                            currentColor = _oklchToRgb(v / 100, current.c, current.h);
                            widget.onColorChanged(currentColor);
                            _syncRgbFromCurrent();
                          });
                        }, max: 100, label: "L"),
                        _buildSlider(_rgbToOklch(currentColor).c, Colors.orange, cController, (double v) {
                          setState(() {
                            final _OKLCH current = _rgbToOklch(currentColor);
                            currentColor = _oklchToRgb(current.l, v, current.h);
                            widget.onColorChanged(currentColor);
                            _syncRgbFromCurrent();
                          });
                        }, max: 0.5, label: "C"),
                        _buildSlider(_rgbToOklch(currentColor).h, Colors.purple, hController, (double v) {
                          setState(() {
                            final _OKLCH current = _rgbToOklch(currentColor);
                            currentColor = _oklchToRgb(current.l, current.c, v);
                            widget.onColorChanged(currentColor);
                            _syncRgbFromCurrent();
                          });
                        }, max: 360, label: "H")
                      ])
                    : Column(children: <Widget>[
                        _buildSlider(currentColor.red8bit.toDouble(), Colors.red, rController, (double v) {
                          setState(() {
                            currentColor = Color.fromARGB(
                                currentColor.alpha8bit, v.toInt(), currentColor.green8bit, currentColor.blue8bit);
                            widget.onColorChanged(currentColor);
                            _syncOklchFromCurrent();
                          });
                        }, label: "R"),
                        _buildSlider(currentColor.green8bit.toDouble(), Colors.green, gController, (double v) {
                          setState(() {
                            currentColor = Color.fromARGB(
                                currentColor.alpha8bit, currentColor.red8bit, v.toInt(), currentColor.blue8bit);
                            widget.onColorChanged(currentColor);
                            _syncOklchFromCurrent();
                          });
                        }, label: "G"),
                        _buildSlider(currentColor.blue8bit.toDouble(), Colors.blue, bController, (double v) {
                          setState(() {
                            currentColor = Color.fromARGB(
                                currentColor.alpha8bit, currentColor.red8bit, currentColor.green8bit, v.toInt());
                            widget.onColorChanged(currentColor);
                            _syncOklchFromCurrent();
                          });
                        }, label: "B")
                      ])),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Text('Theme Palette Sources',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Flexible(
              child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 32,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: colorsList.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Color color = colorsList[index];
                    return InkWell(
                        onTap: () {
                          setState(() {
                            currentColor = color;
                            widget.onColorChanged(currentColor);
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                            decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: onSurface.withValues(alpha: 0.15)),
                        )));
                  }))
        ]));
  }

  _OKLCH get currentColorToOklch => _rgbToOklch(currentColor);

  Widget _buildModeButton(String text, bool active, VoidCallback onTap, Color onSurface) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: active ? onSurface.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? onSurface : onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(double value, Color activeColor, TextEditingController controller, Function(double) onChanged,
      {double max = 255, String label = ""}) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: <Widget>[
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 12,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: activeColor.withValues(alpha: 0.8))),
            ),
          ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: activeColor,
              thumbColor: activeColor,
            ),
            child: Slider(
              value: value.clamp(0, max),
              min: 0,
              max: max,
              onChanged: (double e) {
                onChanged(e);
                final String formatted =
                    max >= 10 && (max % 1 == 0) ? e.toInt().toString() : e.toStringAsFixed(max < 1 ? 3 : 1);
                if (controller.text != formatted) {
                  controller.text = formatted;
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Listener(
          onPointerSignal: (PointerSignalEvent pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final double step = max >= 10 && (max % 1 == 0) ? (max == 360 ? 2 : 2) : 0.01;
              double current = double.tryParse(controller.text) ?? 0;
              current = (current + (pointerSignal.scrollDelta.dy < 0 ? step : -step)).clamp(0, max);
              controller.text =
                  max >= 10 && (max % 1 == 0) ? current.toInt().toString() : current.toStringAsFixed(max < 1 ? 3 : 1);
              onChanged(current);
            }
          },
          child: SizedBox(
            width: 44,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
              onChanged: (String v) {
                double? val = double.tryParse(v);
                if (val != null) {
                  if (val > max) {
                    val = max;
                    controller.text = max.toString();
                    controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                  }
                  onChanged(val);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OKLCH {
  final double l, c, h;
  _OKLCH(this.l, this.c, this.h);
}

class ListColors extends StatefulWidget {
  const ListColors({
    super.key,
    required this.colorsNameMap,
    required this.onColorChanged,
  });

  final Map<ColorSwatch<Object>, String> colorsNameMap;
  final Function(Color) onColorChanged;

  @override
  State<ListColors> createState() => _ListColorsState();
}

class _ListColorsState extends State<ListColors> {
  final ScrollController colorScrollController = ScrollController();

  @override
  void dispose() {
    colorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Listener(
        onPointerSignal: (PointerSignalEvent pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            if (pointerSignal.scrollDelta.dy < 0) {
              colorScrollController.animateTo(colorScrollController.offset - 190,
                  duration: const Duration(milliseconds: 200), curve: Curves.ease);
            } else {
              colorScrollController.animateTo(colorScrollController.offset + 190,
                  duration: const Duration(milliseconds: 200), curve: Curves.ease);
            }
          }
        },
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ShaderMask(
                shaderCallback: (Rect rect) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
                    stops: <double>[0.0, 0.95, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstOut,
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: colorScrollController,
                    child: Row(children: <Widget>[
                      ...widget.colorsNameMap.keys.map((ColorSwatch<Object> color) {
                        return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: InkWell(
                                onTap: () => widget.onColorChanged(color),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: onSurface.withValues(alpha: 0.15)),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                            color: color.withValues(alpha: 0.2),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2))
                                      ],
                                    ))));
                      }),
                      const SizedBox(width: 40)
                    ])))));
  }
}
