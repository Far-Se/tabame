import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// Paired Bluetooth devices with one-click connect/disconnect and battery
/// level — replaces the five-click Settings → Bluetooth round trip.
class BluetoothButton extends StatelessWidget {
  const BluetoothButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Bluetooth",
      icon: const Icon(Icons.bluetooth_rounded),
      child: () => const BluetoothPanel(),
    );
  }
}

class BluetoothPanel extends StatefulWidget {
  const BluetoothPanel({super.key});

  @override
  State<BluetoothPanel> createState() => _BluetoothPanelState();
}

class _BluetoothPanelState extends State<BluetoothPanel> {
  bool _isLoading = true;
  String? _errorMessage;
  List<BluetoothDeviceInfo> _devices = <BluetoothDeviceInfo>[];

  /// Address of the device currently connecting/disconnecting.
  int? _busyAddress;
  final List<Timer> _refreshTimers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    for (final Timer timer in _refreshTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final List<BluetoothDeviceInfo> devices = await WinBluetooth.getDevices();
      if (!mounted) return;
      devices.sort((BluetoothDeviceInfo a, BluetoothDeviceInfo b) {
        if (a.connected != b.connected) return a.connected ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to enumerate devices: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleConnection(BluetoothDeviceInfo device) async {
    if (_busyAddress != null) return;
    setState(() {
      _busyAddress = device.addressRaw;
      _errorMessage = null;
    });
    bool ok = false;
    try {
      ok = await WinBluetooth.setConnection(device, !device.connected);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busyAddress = null;
      if (!ok) {
        _errorMessage = "${device.name}: ${device.connected ? 'disconnect' : 'connect'} failed";
      }
    });
    // The radio takes a moment to settle — refresh twice to catch the final state.
    _refreshTimers.add(Timer(const Duration(milliseconds: 1500), () => _loadDevices(silent: true)));
    _refreshTimers.add(Timer(const Duration(seconds: 4), () => _loadDevices(silent: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        PanelHeader(
          title: "Bluetooth",
          icon: Icons.bluetooth_rounded,
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: "Refresh devices",
          buttonPressed: _isLoading ? null : _loadDevices,
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
    if (_isLoading && _devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_devices.isEmpty) {
      return _buildEmptyState();
    }

    final List<BluetoothDeviceInfo> connected =
        _devices.where((BluetoothDeviceInfo d) => d.connected).toList(growable: false);
    final List<BluetoothDeviceInfo> paired =
        _devices.where((BluetoothDeviceInfo d) => !d.connected).toList(growable: false);

    return WindowsScrollView(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        shrinkWrap: true,
        children: <Widget>[
          if (_errorMessage != null) _buildErrorStrip(_errorMessage!),
          if (connected.isNotEmpty) ...<Widget>[
            _buildSectionLabel("CONNECTED", Icons.bluetooth_connected_rounded, connected.length),
            const SizedBox(height: 6),
            for (final BluetoothDeviceInfo device in connected) _buildDeviceCard(device),
            const SizedBox(height: 6),
          ],
          _buildSectionLabel("PAIRED", Icons.bluetooth_rounded, paired.length),
          const SizedBox(height: 6),
          for (final BluetoothDeviceInfo device in paired) _buildDeviceCard(device),
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
          Icon(Icons.bluetooth_disabled_rounded, size: 32, color: Design.text.withAlpha(90)),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? "No paired Bluetooth devices found",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(140)),
          ),
          const SizedBox(height: 4),
          Text(
            "Pair devices in Windows Settings first — this panel handles the daily connect/disconnect.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 12, color: Design.text.withAlpha(90)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Connect toggles the device's Bluetooth services — audio devices respond best. Battery shows when the device reports it.",
              style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(110)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon, int count) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
          child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  IconData _deviceIcon(BluetoothDeviceInfo device) {
    final int majorClass = (device.classOfDevice >> 8) & 0x1F;
    switch (majorClass) {
      case 1:
        return Icons.computer_rounded;
      case 2:
        return Icons.smartphone_rounded;
      case 4:
        return Icons.headphones_rounded;
      case 5:
        final int minor = (device.classOfDevice >> 6) & 0x3;
        if (minor == 1) return Icons.keyboard_rounded;
        if (minor == 2) return Icons.mouse_rounded;
        return Icons.gamepad_rounded;
      case 6:
        return Icons.print_rounded;
      default:
        return Icons.bluetooth_rounded;
    }
  }

  Color _batteryColor(int battery) {
    if (battery >= 50) return Colors.greenAccent.shade400;
    if (battery >= 20) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _buildDeviceCard(BluetoothDeviceInfo device) {
    final bool connected = device.connected;
    final bool busy = _busyAddress == device.addressRaw;
    final bool anyBusy = _busyAddress != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: connected ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: connected ? Design.accent.withAlpha(30) : Design.text.withAlpha(16),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (connected ? Design.accent : Design.text).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _deviceIcon(device),
              size: 16,
              color: connected ? Design.accent : Design.text.withAlpha(160),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  device.address,
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    letterSpacing: 0.4,
                    color: Design.text.withAlpha(100),
                  ),
                ),
              ],
            ),
          ),
          if (device.battery >= 0) ...<Widget>[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _batteryColor(device.battery).withAlpha(24),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    device.battery >= 20 ? Icons.battery_std_rounded : Icons.battery_alert_rounded,
                    size: 11,
                    color: _batteryColor(device.battery),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    "${device.battery}%",
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      fontWeight: FontWeight.w700,
                      color: _batteryColor(device.battery),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 6),
          InkWell(
            onTap: anyBusy ? null : () => _toggleConnection(device),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: connected ? Design.text.withAlpha(10) : Design.accent.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: connected ? Design.text.withAlpha(30) : Design.accent.withAlpha(80),
                ),
              ),
              child: busy
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : Text(
                      connected ? "Disconnect" : "Connect",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: connected ? Design.text.withAlpha(170) : Design.accent,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
