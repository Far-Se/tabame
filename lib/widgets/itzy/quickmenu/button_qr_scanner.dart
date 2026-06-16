import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/qr_capture_decoder.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class QrScannerButton extends StatelessWidget {
  const QrScannerButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "QR Scanner", icon: const Icon(Icons.qr_code_scanner_rounded), child: () => const QrScannerPanel());
  }
}

class QrScannerPanel extends StatefulWidget {
  final bool justScanned;
  const QrScannerPanel({super.key, this.justScanned = false});

  @override
  State<QrScannerPanel> createState() => _QrScannerPanelState();
}

class _QrScannerPanelState extends State<QrScannerPanel> {
  bool _busy = false;
  bool _copied = false;
  String? _result;
  String? _errorMessage;
  String? _infoMessage;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.justScanned) {
      _scanQrCode(justScanned: true);
    }
  }

  Future<void> _scanQrCode({bool justScanned = false}) async {
    setState(() {
      _busy = true;
      _copied = false;
      _errorMessage = null;
      _infoMessage = 'Capture the QR code on screen.';
    });

    try {
      QuickMenuFunctions.keepOpen = true;
      await WinUtils.screenCapture();

      Timer(const Duration(milliseconds: 1000), () async {
        QuickMenuFunctions.keepOpen = false;
      });
      //   await QuickMenuFunctions.toggleQuickMenu(visible: true);
      //   await Future<void>.delayed(const Duration(milliseconds: 260));
      //   QuickMenuFunctions.triggerQuickAction("QrScanner");
      // });

      final String capturePath = "${WinUtils.getTempFolder()}\\capture.png";
      final File captureFile = File(capturePath);
      if (!captureFile.existsSync()) {
        throw const FormatException('No capture image was saved.');
      }

      final String? decoded = await compute<String, String?>(
        decodeQrValueFromCapturedPng,
        capturePath,
      );

      if (decoded == null || decoded.trim().isEmpty) {
        throw const FormatException('No QR code could be read from the capture.');
      }

      if (!mounted) return;
      setState(() {
        _result = decoded.trim();
        _infoMessage = 'QR code decoded.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FormatException ? e.message : 'Unable to capture and scan the QR code.';
        _infoMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _copyResult() async {
    final String? result = _result;
    if (result == null || result.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: result));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: "QR Scanner",
          icon: Icons.qr_code_scanner_rounded,
          buttonPressed: _busy ? null : _scanQrCode,
          buttonIcon: Icons.screenshot_monitor_rounded,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 1.5),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withAlpha(28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          "Capture a QR code from the screen and show only the decoded output.",
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            height: 1.3,
                            color: onSurface.withAlpha(190),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _scanQrCode,
                          icon: const Icon(Icons.screenshot_monitor_rounded, size: 16),
                          label: Text(_result == null ? "Scan QR Code" : "Scan Again"),
                        ),
                      ],
                    ),
                  ),
                  if (_infoMessage != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _QrStatusStrip(
                      message: _infoMessage!,
                      accent: accent,
                      background: accent.withAlpha(16),
                    ),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _QrStatusStrip(
                      message: _errorMessage!,
                      accent: Colors.redAccent,
                      background: Colors.redAccent.withAlpha(24),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_result == null) _buildEmptyState(accent, onSurface) else _buildResultCard(accent, onSurface),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withAlpha(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.qr_code_2_rounded, size: 32, color: accent.withAlpha(150)),
          const SizedBox(height: 10),
          Text(
            "No result yet",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Start a capture and select the QR code area on screen.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 1,
              height: 1.35,
              color: onSurface.withAlpha(155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Color accent, Color onSurface) {
    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(28)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _copyResult,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.data_object_rounded, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Decoded Output",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                  ),
                  Text(
                    _copied ? "Copied" : "Tap to copy",
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      fontWeight: FontWeight.w600,
                      color: _copied ? accent : onSurface.withAlpha(145),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                _result ?? '',
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  height: 1.4,
                  color: onSurface.withAlpha(220),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrStatusStrip extends StatelessWidget {
  const _QrStatusStrip({
    required this.message,
    required this.accent,
    required this.background,
  });

  final String message;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
