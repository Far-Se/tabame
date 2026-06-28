import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/qr_capture_decoder.dart';
import '../../../models/util/qr_generator.dart';
import '../../../models/win32/win32.dart';
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

enum _QrMode { scan, generate }

class QrScannerPanel extends StatefulWidget {
  final bool justScanned;
  const QrScannerPanel({super.key, this.justScanned = false});

  @override
  State<QrScannerPanel> createState() => _QrScannerPanelState();
}

class _QrScannerPanelState extends State<QrScannerPanel> {
  _QrMode _mode = _QrMode.scan;

  bool _busy = false;
  bool _copied = false;
  String? _result;
  String? _errorMessage;
  String? _infoMessage;
  Timer? _copiedTimer;

  final TextEditingController _generateController = TextEditingController();
  Uint8List? _generatedPngBytes;
  bool _generatedImageCopied = false;
  Timer? _generatedCopiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _generatedCopiedTimer?.cancel();
    _generateController.dispose();
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

      ShowWindow(Win32.hWnd, SW_HIDE);
      await WinUtils.screenCapture();
      ShowWindow(Win32.hWnd, SW_SHOW);

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

  Future<void> _generateQrCode() async {
    final String content = _generateController.text.trim();
    if (content.isEmpty) {
      setState(() {
        _generatedPngBytes = null;
        _errorMessage = 'Enter some text or a URL to generate a QR code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _generatedImageCopied = false;
    });

    try {
      final img.Image? image = await compute(_buildQrImage, content);
      if (image == null) throw const FormatException('Could not generate a QR code for this content.');

      if (!mounted) return;
      setState(() {
        _generatedPngBytes = img.encodePng(image);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generatedPngBytes = null;
        _errorMessage = e is FormatException ? e.message : 'Unable to generate a QR code.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyGeneratedImage() async {
    final Uint8List? pngBytes = _generatedPngBytes;
    if (pngBytes == null) return;

    await ClipboardExtended.copyImage(pngBytes);
    if (!mounted) return;
    setState(() => _generatedImageCopied = true);
    _generatedCopiedTimer?.cancel();
    _generatedCopiedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _generatedImageCopied = false);
    });
  }

  void _setMode(_QrMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _errorMessage = null;
      _infoMessage = null;
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
          title: _mode == _QrMode.scan ? "QR Scanner" : "QR Generator",
          icon: Icons.qr_code_scanner_rounded,
          buttonPressed: _busy
              ? null
              : _mode == _QrMode.scan
                  ? _scanQrCode
                  : _generateQrCode,
          buttonIcon: _mode == _QrMode.scan ? Icons.screenshot_monitor_rounded : Icons.qr_code_2_rounded,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 1.5),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: ToggleButtons(
            isSelected: <bool>[_mode == _QrMode.scan, _mode == _QrMode.generate],
            onPressed: (int index) => _setMode(_QrMode.values[index]),
            borderRadius: BorderRadius.circular(8),
            selectedColor: accent,
            fillColor: accent.withAlpha(18),
            color: onSurface.withAlpha(160),
            textStyle: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600),
            constraints: const BoxConstraints(minHeight: 30),
            children: const <Widget>[
              Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text("Scan")),
              Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text("Generate")),
            ],
          ),
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _mode == _QrMode.scan
                  ? _buildScanBody(accent, onSurface)
                  : _buildGenerateBody(accent, onSurface),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanBody(Color accent, Color onSurface) {
    return Column(
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
    );
  }

  Widget _buildGenerateBody(Color accent, Color onSurface) {
    return Column(
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
                "Enter text, a URL, or any content to turn into a QR code.",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  height: 1.3,
                  color: onSurface.withAlpha(190),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _generateController,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _generateQrCode(),
                decoration: InputDecoration(
                  hintText: "https://example.com",
                  isDense: true,
                  filled: true,
                  fillColor: onSurface.withAlpha(8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: onSurface.withAlpha(24)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _generateQrCode,
                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                label: const Text("Generate QR Code"),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          _QrStatusStrip(
            message: _errorMessage!,
            accent: Colors.redAccent,
            background: Colors.redAccent.withAlpha(24),
          ),
        ],
        const SizedBox(height: 12),
        if (_generatedPngBytes == null) _buildGenerateEmptyState(accent, onSurface) else _buildGeneratedCard(accent, onSurface),
      ],
    );
  }

  Widget _buildGenerateEmptyState(Color accent, Color onSurface) {
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
            "No QR code yet",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            "Type some content above and generate a QR code.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 1, height: 1.35, color: onSurface.withAlpha(155)),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedCard(Color accent, Color onSurface) {
    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(_generatedPngBytes!, width: 180, height: 180, gaplessPlayback: true),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _copyGeneratedImage,
              icon: Icon(_generatedImageCopied ? Icons.check_rounded : Icons.copy_rounded, size: 16),
              label: Text(_generatedImageCopied ? "Copied" : "Copy Image"),
            ),
          ],
        ),
      ),
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

img.Image? _buildQrImage(String content) => buildQrImage(content);

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
