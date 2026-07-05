import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class DevToolboxButton extends StatelessWidget {
  const DevToolboxButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Dev Toolbox",
      icon: const Icon(Icons.terminal_rounded),
      child: () => const DevToolboxWidget(),
    );
  }
}

enum _Tool {
  base64Encode("Base64 →", true),
  base64Decode("→ Base64", true),
  urlEncode("URL →", true),
  urlDecode("→ URL", true),
  jsonFormat("JSON ↔", true),
  jsonMinify("JSON min", true),
  md5Hash("MD5", true),
  sha1Hash("SHA-1", true),
  sha256Hash("SHA-256", true),
  uuid("UUID v4", false),
  timestamp("Timestamp", true);

  const _Tool(this.label, this.usesInput);
  final String label;
  final bool usesInput;
}

class DevToolboxWidget extends StatefulWidget {
  const DevToolboxWidget({super.key});

  @override
  State<DevToolboxWidget> createState() => _DevToolboxWidgetState();
}

class _DevToolboxWidgetState extends State<DevToolboxWidget> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  _Tool _tool = _Tool.base64Encode;
  String _output = "";
  String? _error;
  String _uuidValue = "";

  @override
  void initState() {
    super.initState();
    _uuidValue = _generateUuid();
    _input.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _recompute();
    });
  }

  @override
  void dispose() {
    _input.removeListener(_recompute);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _selectTool(_Tool tool) {
    setState(() {
      _tool = tool;
      if (tool == _Tool.uuid) _uuidValue = _generateUuid();
    });
    _recompute();
  }

  void _recompute() {
    try {
      setState(() {
        _output = _process(_tool, _input.text);
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _output = "";
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _output = "";
        _error = e.toString();
      });
    }
  }

  String _process(_Tool tool, String input) {
    switch (tool) {
      case _Tool.base64Encode:
        return base64.encode(utf8.encode(input));
      case _Tool.base64Decode:
        return utf8.decode(base64.decode(input.trim()));
      case _Tool.urlEncode:
        return Uri.encodeComponent(input);
      case _Tool.urlDecode:
        return Uri.decodeComponent(input);
      case _Tool.jsonFormat:
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(input));
      case _Tool.jsonMinify:
        return jsonEncode(jsonDecode(input));
      case _Tool.md5Hash:
        return md5.convert(utf8.encode(input)).toString();
      case _Tool.sha1Hash:
        return sha1.convert(utf8.encode(input)).toString();
      case _Tool.sha256Hash:
        return sha256.convert(utf8.encode(input)).toString();
      case _Tool.uuid:
        return _uuidValue;
      case _Tool.timestamp:
        return _timestamp(input);
    }
  }

  String _timestamp(String input) {
    final String t = input.trim();
    if (t.isEmpty) {
      final DateTime now = DateTime.now();
      return "Unix (s): ${now.millisecondsSinceEpoch ~/ 1000}\n"
          "Unix (ms): ${now.millisecondsSinceEpoch}\n"
          "ISO: ${now.toIso8601String()}";
    }
    final int? n = int.tryParse(t);
    if (n != null) {
      final int ms = t.length > 11 ? n : n * 1000;
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return "Local: $dt\nUTC: ${dt.toUtc().toIso8601String()}";
    }
    final DateTime? dt = DateTime.tryParse(t);
    if (dt != null) {
      return "Unix (s): ${dt.millisecondsSinceEpoch ~/ 1000}\n"
          "Unix (ms): ${dt.millisecondsSinceEpoch}";
    }
    throw const FormatException("Enter a unix timestamp or an ISO date.");
  }

  String _generateUuid() {
    final Random r = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final String h = bytes.map(hex).join();
    return "${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-"
        "${h.substring(16, 20)}-${h.substring(20)}";
  }

  void _copyOutput() {
    if (_output.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _output));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: C.stretch,
        children: <Widget>[
          PanelHeader(
            title: "Dev Toolbox",
            icon: Icons.terminal_rounded,
            buttonIcon: _tool == _Tool.uuid ? Icons.refresh_rounded : null,
            buttonTooltip: "New UUID",
            buttonPressed: _tool == _Tool.uuid ? () => _selectTool(_Tool.uuid) : null,
          ),
          Flexible(
            child: WindowsScrollView(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  _buildToolChips(),
                  const SizedBox(height: 12),
                  if (_tool.usesInput) ...<Widget>[
                    _buildInput(),
                    const SizedBox(height: 12),
                  ],
                  _buildOutput(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolChips() {
    final Color accent = Design.accent;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final _Tool tool in _Tool.values)
          GestureDetector(
            onTap: () => _selectTool(tool),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _tool == tool ? accent.withAlpha(36) : Design.text.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _tool == tool ? accent.withAlpha(120) : Design.text.withAlpha(18),
                ),
              ),
              child: Text(
                tool.label,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: FontWeight.w700,
                  color: _tool == tool ? accent : Design.text.withAlpha(180),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInput() {
    final Color accent = Design.accent;
    return TextField(
      controller: _input,
      focusNode: _focus,
      autofocus: true,
      minLines: 3,
      maxLines: 8,
      style: const TextStyle(fontSize: 13, fontFamily: "monospace"),
      decoration: InputDecoration(
        isDense: true,
        hintText: "Input…",
        filled: true,
        fillColor: accent.withAlpha(10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withAlpha(90), width: 1),
        ),
      ),
    );
  }

  Widget _buildOutput() {
    final Color accent = Design.accent;
    final bool hasError = _error != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                "OUTPUT",
                style: TextStyle(
                  fontSize: Design.baseFontSize - 0.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Design.text.withAlpha(120),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _copyOutput,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.content_copy_rounded, size: 14, color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            hasError ? _error! : (_output.isEmpty ? "—" : _output),
            style: TextStyle(
              fontSize: 13,
              fontFamily: "monospace",
              height: 1.35,
              color: hasError ? Colors.orangeAccent.withAlpha(220) : Design.text,
            ),
          ),
        ],
      ),
    );
  }
}
