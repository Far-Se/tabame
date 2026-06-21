import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/ocr_capture_decoder.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class OcrButton extends StatelessWidget {
  const OcrButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(actionName: "OCR", icon: const Icon(Icons.text_snippet_outlined), child: () => const OcrPanel());
  }
}

class OcrPanel extends StatefulWidget {
  const OcrPanel({super.key});

  @override
  State<OcrPanel> createState() => _OcrPanelState();
}

class _OcrPanelState extends State<OcrPanel> {
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

  Future<void> _captureText() async {
    setState(() {
      _busy = true;
      _copied = false;
      _errorMessage = null;
      _infoMessage = 'Capture the text on screen.';
    });

    final String capturePath = "${WinUtils.getTempFolder()}\\capture.png";

    try {
      QuickMenuFunctions.keepOpen = true;

      ShowWindow(Win32.hWnd, SW_HIDE);
      await WinUtils.screenCapture();

      ShowWindow(Win32.hWnd, SW_SHOW);
      Timer(const Duration(milliseconds: 1000), () async {
        QuickMenuFunctions.keepOpen = false;
      });

      final File captureFile = File(capturePath);
      if (!captureFile.existsSync()) {
        throw const FormatException('No capture image was saved.');
      }

      final String? recognized = await recognizeTextFromCapturedPng(capturePath);
      if (recognized == null || recognized.isEmpty) {
        throw const FormatException('No text could be recognized from the capture.');
      }

      if (!mounted) return;
      setState(() {
        _result = recognized;
        _infoMessage = 'Text recognized.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FormatException ? e.message : 'Unable to capture and recognize text.';
        _infoMessage = null;
      });
    } finally {
      final File captureFile = File(capturePath);
      if (captureFile.existsSync()) {
        captureFile.deleteSync();
      }
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
          title: "OCR",
          icon: Icons.text_snippet_outlined,
          buttonPressed: _busy ? null : _captureText,
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
                          "Capture a region of the screen and extract any text it contains.",
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            height: 1.3,
                            color: onSurface.withAlpha(190),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _captureText,
                          icon: const Icon(Icons.screenshot_monitor_rounded, size: 16),
                          label: Text(_result == null ? "Capture Text" : "Capture Again"),
                        ),
                      ],
                    ),
                  ),
                  if (_infoMessage != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _OcrStatusStrip(
                      message: _infoMessage!,
                      accent: accent,
                      background: accent.withAlpha(16),
                    ),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _OcrStatusStrip(
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
          Icon(Icons.text_snippet_outlined, size: 32, color: accent.withAlpha(150)),
          const SizedBox(height: 10),
          Text(
            "No text yet",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Start a capture and select the area on screen that has the text.",
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
                  Icon(Icons.notes_rounded, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Recognized Text",
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

class _OcrStatusStrip extends StatelessWidget {
  const _OcrStatusStrip({
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
