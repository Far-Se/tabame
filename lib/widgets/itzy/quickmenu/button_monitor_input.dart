import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// Software KVM: switches a monitor's active input source over DDC/CI
/// (VESA MCCS VCP code 0x60) — the same command a hardware KVM sends.
class MonitorInputButton extends StatelessWidget {
  const MonitorInputButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Monitor Input",
      icon: const Icon(Icons.settings_input_hdmi_rounded),
      child: () => const MonitorInputPanel(),
    );
  }
}

/// Standard MCCS input source codes (VCP 0x60). Vendor-specific codes fall
/// back to a hex label.
const Map<int, String> _inputNames = <int, String>{
  0x01: "VGA 1",
  0x02: "VGA 2",
  0x03: "DVI 1",
  0x04: "DVI 2",
  0x05: "Composite 1",
  0x06: "Composite 2",
  0x07: "S-Video 1",
  0x08: "S-Video 2",
  0x09: "Tuner 1",
  0x0A: "Tuner 2",
  0x0B: "Tuner 3",
  0x0C: "Component 1",
  0x0D: "Component 2",
  0x0E: "Component 3",
  0x0F: "DisplayPort 1",
  0x10: "DisplayPort 2",
  0x11: "HDMI 1",
  0x12: "HDMI 2",
  0x1B: "USB-C",
};

/// Offered when a monitor answers VCP 0x60 but doesn't advertise a parsable
/// capabilities string.
const List<int> _fallbackInputs = <int>[0x11, 0x12, 0x0F, 0x10, 0x03, 0x01];

String _inputLabel(int code) => _inputNames[code] ?? "0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}";

class MonitorInputPanel extends StatefulWidget {
  const MonitorInputPanel({super.key});

  @override
  State<MonitorInputPanel> createState() => _MonitorInputPanelState();
}

class _MonitorInputPanelState extends State<MonitorInputPanel> {
  bool _isLoading = true;
  String? _errorMessage;
  List<MonitorInputDisplay> _displays = <MonitorInputDisplay>[];

  // displayId currently being switched, and the target code — drives the
  // per-chip progress indicator.
  String? _switchingId;
  int? _switchingCode;

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
      final List<MonitorInputDisplay> displays = await WinMonitorInput.getDisplays();
      if (!mounted) return;
      setState(() {
        _displays = displays;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to probe displays: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _switchInput(MonitorInputDisplay display, int code) async {
    if (_switchingId != null) return;
    setState(() {
      _switchingId = display.id;
      _switchingCode = code;
      _errorMessage = null;
    });
    bool ok = false;
    try {
      ok = await WinMonitorInput.setInput(display, code);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _switchingId = null;
      _switchingCode = null;
      if (ok) {
        _displays = _displays
            .map((MonitorInputDisplay d) => d.id == display.id
                ? MonitorInputDisplay(
                    id: d.id,
                    name: d.name,
                    supported: d.supported,
                    current: code,
                    available: d.available,
                  )
                : d)
            .toList(growable: false);
      } else {
        _errorMessage = "${display.name} rejected the switch to ${_inputLabel(code)}";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        PanelHeader(
          title: "Monitor Input",
          icon: Icons.settings_input_hdmi_rounded,
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: "Re-probe displays",
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            const SizedBox(height: 12),
            Text(
              "Probing DDC/CI — can take a few seconds",
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(120)),
            ),
          ],
        ),
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
          for (final MonitorInputDisplay display in _displays) ...<Widget>[
            _buildDisplayCard(display),
            const SizedBox(height: 8),
          ],
          _buildHintStrip(),
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
            _errorMessage ?? "No DDC/CI-capable displays detected",
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

  Widget _buildHintStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 12, color: Design.text.withAlpha(90)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Switching moves the monitor to another device — switch back from that device or the monitor's own menu.",
              style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(110)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayCard(MonitorInputDisplay display) {
    final bool supported = display.supported;
    final List<int> inputs = <int>[
      if (supported) ...display.available.isNotEmpty ? display.available : _fallbackInputs,
    ];
    if (supported && !inputs.contains(display.current)) inputs.insert(0, display.current);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (supported ? Design.accent : Design.text).withAlpha(20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  supported ? _inputLabel(display.current) : "NO DDC/CI",
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: supported ? Design.accent : Design.text.withAlpha(110),
                  ),
                ),
              ),
            ],
          ),
          if (supported) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final int code in inputs) _buildInputChip(display, code),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputChip(MonitorInputDisplay display, int code) {
    final bool isCurrent = code == display.current;
    final bool isSwitching = _switchingId == display.id && _switchingCode == code;
    final bool busy = _switchingId != null;

    return InkWell(
      onTap: isCurrent || busy ? null : () => _switchInput(display, code),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrent ? Design.accent.withAlpha(28) : Design.text.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent ? Design.accent.withAlpha(80) : Design.text.withAlpha(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSwitching) ...<Widget>[
              const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 6),
            ] else if (isCurrent) ...<Widget>[
              Icon(Icons.check_rounded, size: 12, color: Design.accent),
              const SizedBox(width: 4),
            ],
            Text(
              _inputLabel(code),
              style: TextStyle(
                fontSize: Design.baseFontSize + 0.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: isCurrent ? Design.accent : Design.text.withAlpha(busy && !isSwitching ? 110 : 200),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
