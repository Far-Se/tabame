import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class BrightnessButton extends StatelessWidget {
  const BrightnessButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Brightness",
      icon: const Icon(Icons.brightness_6_rounded),
      child: () => const BrightnessPanel(),
    );
  }
}

class BrightnessPanel extends StatefulWidget {
  const BrightnessPanel({super.key});

  @override
  State<BrightnessPanel> createState() => _BrightnessPanelState();
}

class _BrightnessPanelState extends State<BrightnessPanel> {
  bool _isLoading = true;
  String? _errorMessage;
  List<BrightnessDisplay> _displays = <BrightnessDisplay>[];

  // Live slider values keyed by display id (so dragging is smooth while the
  // debounced native write catches up).
  final Map<String, double> _values = <String, double>{};
  final Map<String, Timer> _debounce = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _loadDisplays();
  }

  @override
  void dispose() {
    for (final Timer t in _debounce.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _loadDisplays() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final List<BrightnessDisplay> displays = await WinBrightness.getDisplays();
      if (!mounted) return;
      setState(() {
        _displays = displays;
        _values
          ..clear()
          ..addEntries(displays.map(
            (BrightnessDisplay d) => MapEntry<String, double>(d.id, d.current.toDouble()),
          ));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to read displays: $e";
        _isLoading = false;
      });
    }
  }

  void _onSliderChanged(BrightnessDisplay display, double value) {
    setState(() => _values[display.id] = value);
    _debounce[display.id]?.cancel();
    _debounce[display.id] = Timer(const Duration(milliseconds: 120), () {
      WinBrightness.setBrightness(display, value.round());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        PanelHeader(
          title: "Brightness",
          icon: Icons.brightness_6_rounded,
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: "Refresh",
          buttonPressed: _isLoading ? null : _loadDisplays,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_displays.isEmpty) {
      return _buildEmptyState();
    }

    return WindowsScrollView(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        shrinkWrap: true,
        children: <Widget>[
          if (_errorMessage != null) _buildErrorStrip(_errorMessage!),
          for (final BrightnessDisplay display in _displays) ...<Widget>[
            _buildDisplayCard(display),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.brightness_low_rounded, size: 32, color: Design.text.withAlpha(90)),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? "No adjustable displays detected",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(140)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStrip(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withAlpha(70)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: Design.baseFontSize, color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayCard(BrightnessDisplay display) {
    final bool supported = display.supported && display.max > display.min;
    final double value = _values[display.id] ?? display.current.toDouble();
    final int percent = supported ? (((value - display.min) / (display.max - display.min)) * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
      decoration: BoxDecoration(
        color: supported ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: supported ? Design.accent.withAlpha(30) : Design.text.withAlpha(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (supported ? Design.accent : Design.text).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.monitor_rounded,
                  size: 16,
                  color: supported ? Design.accent : Design.text.withAlpha(160),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  display.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                supported ? "$percent%" : "N/A",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: FontWeight.w700,
                  color: supported ? Design.accent : Design.text.withAlpha(110),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: Design.accent,
              inactiveTrackColor: Design.text.withAlpha(28),
              thumbColor: Design.accent,
            ),
            child: Slider(
              value: value.clamp(display.min.toDouble(), display.max.toDouble()),
              min: display.min.toDouble(),
              max:
                  display.max.toDouble() > display.min.toDouble() ? display.max.toDouble() : display.min.toDouble() + 1,
              onChanged: supported ? (double v) => _onSliderChanged(display, v) : null,
            ),
          ),
        ],
      ),
    );
  }
}
