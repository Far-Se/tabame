import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/settings.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class HDRButton extends StatelessWidget {
  const HDRButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "HDR",
      icon: const Icon(Icons.hdr_on_rounded),
      child: () => const HDRPanel(),
    );
  }
}

class HDRPanel extends StatefulWidget {
  const HDRPanel({super.key});

  @override
  State<HDRPanel> createState() => _HDRPanelState();
}

class _HDRPanelState extends State<HDRPanel> {
  bool _isLoading = true;
  String? _errorMessage;
  List<HDRDisplay> _displays = <HDRDisplay>[];

  // Identity key of the display currently being toggled (null when idle).
  String? _pendingKey;

  String _keyOf(HDRDisplay d) => "${d.adapterIdLow}:${d.adapterIdHigh}:${d.id}";

  @override
  void initState() {
    super.initState();
    _loadDisplays();
  }

  Future<void> _loadDisplays() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final List<HDRDisplay> displays = await HDR.getDisplays();
      if (!mounted) return;
      setState(() {
        _displays = displays;
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

  Future<void> _toggle(HDRDisplay display) async {
    if (!display.supportsHDR || _pendingKey != null) return;
    final String key = _keyOf(display);
    setState(() => _pendingKey = key);

    final bool ok = await HDR.setState(display, !display.isHDREnabled);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _pendingKey = null;
        _errorMessage = "Couldn't toggle HDR for ${display.name}.";
      });
      return;
    }

    // Re-query so the reported state reflects what the driver actually applied.
    try {
      final List<HDRDisplay> displays = await HDR.getDisplays();
      if (!mounted) return;
      setState(() {
        _displays = displays;
        _pendingKey = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        PanelHeader(
          title: "HDR",
          icon: Icons.hdr_on_rounded,
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
          for (final HDRDisplay display in _displays) ...<Widget>[
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
          Icon(Icons.desktop_access_disabled_rounded, size: 32, color: Design.text.withAlpha(90)),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? "No displays detected",
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

  Widget _buildDisplayCard(HDRDisplay display) {
    final bool supported = display.supportsHDR;
    final bool enabled = display.isHDREnabled;
    final bool pending = _pendingKey == _keyOf(display);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: supported && enabled ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: supported && enabled ? Design.accent.withAlpha(30) : Design.text.withAlpha(16),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (supported && enabled ? Design.accent : Design.text).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.monitor_rounded,
              size: 16,
              color: supported && enabled ? Design.accent : Design.text.withAlpha(160),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  display.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !supported ? "HDR NOT SUPPORTED" : (enabled ? "HDR ON" : "HDR OFF"),
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 0.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: !supported
                        ? Design.text.withAlpha(90)
                        : (enabled ? Design.accent : Design.text.withAlpha(120)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          pending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : MiniToggleSwitch(
                  value: enabled,
                  activeThumbColor: Design.accent,
                  onChanged: supported ? (_) => _toggle(display) : null,
                ),
        ],
      ),
    );
  }
}
