import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/settings.dart';
import 'win32_helper.dart';

/// Colours — matches the PowerShell palette 1-to-1.
class _Pal {
  static const ui.Color bg = Color(0xFF121214);
  static const ui.Color border = Color(0xFF373741);
  static const ui.Color textSec = Color(0xFF8C8CA0);
  static const ui.Color copied = Color(0xFF64D282);
  static const ui.Color gridLine = Color(0x28FFFFFF);
  static const ui.Color colR = Color(0xFFFF5A50);
  static const ui.Color colG = Color(0xFF50C864);
  static const ui.Color colB = Color(0xFF5096FF);
  static const ui.Color white = Color(0xFFFFFFFF);
}

/// Mirrors the PS layout constants exactly.
class _Layout {
  static const double zoom = 11.0;
  static const int gridSize = 11;
  static const int half = 5; // floor(11/2)
  static const double pad = 8.0;
  static const double gridPx = gridSize * zoom; // 121
  static const double swatchH = 28.0;
  static const double innerW = gridPx;

  // Derived positions
  static const double gridX = pad;
  static const double gridY = pad;
  static const double gridRight = gridX + gridPx;
  static const double gridBot = gridY + gridPx;
  static const double divY = gridBot + 3;
  static const double swatchY = divY + 1;
  static const double swatchW = 28.0;
  static const double swatchPad = 4.0;
  static const double swatchRX = pad;
  static const double swatchRY = swatchY + swatchPad;
  static const double swatchRH = swatchH - swatchPad * 2;
  static const double hexX = pad + swatchW + 7;
  static const double hexY = swatchY + 5;
  static const double div2Y = swatchY + swatchH;
  static const double rgbY = div2Y + 3;
  static const double lineEnd = pad + innerW;
  static const double colW = innerW / 3;

  // Crosshair centre pixel top-left
  static const double cxCross = gridX + half * zoom;
  static const double cyCross = gridY + half * zoom;

  // Swatch rounded-rect radius
  static const double swatchR = 6.0;
}

class ColorPickerPainter extends CustomPainter {
  final List<List<PixelColor>> grid;
  final PixelColor center;
  final bool copied;

  ColorPickerPainter({
    required this.grid,
    required this.center,
    required this.copied,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawPixelGrid(canvas);
    _drawGridLines(canvas);
    _drawCrosshair(canvas);
    _drawDivider(canvas, _Layout.divY);
    _drawSwatch(canvas);
    _drawHexLabel(canvas);
    _drawDivider(canvas, _Layout.div2Y);
    _drawRgbRow(canvas);
  }

  // ── Background ──────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    final ui.Paint paint = Paint()..color = _Pal.bg;
    final ui.RRect rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(rr, paint);
  }

  // ── 11×11 pixel grid ────────────────────────────────────────────────────

  void _drawPixelGrid(Canvas canvas) {
    const double zoom = _Layout.zoom;
    for (int row = 0; row < _Layout.gridSize; row++) {
      for (int col = 0; col < _Layout.gridSize; col++) {
        final PixelColor px = grid[row][col];
        final ui.Paint paint = Paint()..color = Color.fromARGB(255, px.r, px.g, px.b);
        canvas.drawRect(
          Rect.fromLTWH(
            _Layout.gridX + col * zoom,
            _Layout.gridY + row * zoom,
            zoom,
            zoom,
          ),
          paint,
        );
      }
    }
  }

  // ── Translucent grid lines ───────────────────────────────────────────────

  void _drawGridLines(Canvas canvas) {
    final ui.Paint paint = Paint()
      ..color = _Pal.gridLine
      ..strokeWidth = 1;

    // Horizontal
    for (int i = 0; i <= _Layout.gridSize; i++) {
      final double y = _Layout.gridY + i * _Layout.zoom;
      canvas.drawLine(
        Offset(_Layout.gridX, y),
        Offset(_Layout.gridRight, y),
        paint,
      );
    }
    // Vertical
    for (int i = 0; i <= _Layout.gridSize; i++) {
      final double x = _Layout.gridX + i * _Layout.zoom;
      canvas.drawLine(
        Offset(x, _Layout.gridY),
        Offset(x, _Layout.gridBot),
        paint,
      );
    }
  }

  // ── Crosshair over centre cell ───────────────────────────────────────────

  void _drawCrosshair(Canvas canvas) {
    final ui.Paint outer = Paint()
      ..color = _Pal.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final ui.Paint inner = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Outer white rectangle
    canvas.drawRect(
      const Rect.fromLTWH(
        _Layout.cxCross,
        _Layout.cyCross,
        _Layout.zoom,
        _Layout.zoom,
      ),
      outer,
    );
    // Inner black rectangle (1 px inset)
    canvas.drawRect(
      const Rect.fromLTWH(
        _Layout.cxCross + 1,
        _Layout.cyCross + 1,
        _Layout.zoom - 2,
        _Layout.zoom - 2,
      ),
      inner,
    );
  }

  // ── Horizontal dividers ──────────────────────────────────────────────────

  void _drawDivider(Canvas canvas, double y) {
    final ui.Paint paint = Paint()
      ..color = _Pal.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_Layout.pad, y),
      Offset(_Layout.lineEnd, y),
      paint,
    );
  }

  // ── Colour swatch (rounded rect) ────────────────────────────────────────

  void _drawSwatch(Canvas canvas) {
    final ui.RRect rr = RRect.fromRectAndRadius(
      const Rect.fromLTWH(
        _Layout.swatchRX,
        _Layout.swatchRY,
        _Layout.swatchW,
        _Layout.swatchRH,
      ),
      const Radius.circular(_Layout.swatchR),
    );
    final ui.Paint fill = Paint()..color = Color.fromARGB(255, center.r, center.g, center.b);
    final ui.Paint stroke = Paint()
      ..color = _Pal.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);
  }

  // ── Hex / "Copied!" label ────────────────────────────────────────────────

  void _drawHexLabel(Canvas canvas) {
    final String text = copied ? 'Copied!' : center.hex;
    final ui.Color color = copied ? _Pal.copied : _Pal.white;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: Design.baseFontSize + 1,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(_Layout.hexX, _Layout.hexY));
  }

  // ── RGB row ──────────────────────────────────────────────────────────────

  void _drawRgbRow(Canvas canvas) {
    const List<String> labels = <String>['R', 'G', 'B'];
    const List<ui.Color> colors = <ui.Color>[_Pal.colR, _Pal.colG, _Pal.colB];
    final List<int> values = <int>[center.r, center.g, center.b];

    for (int i = 0; i < 3; i++) {
      final double labelX = _Layout.pad + i * _Layout.colW;
      final double valueX = labelX + 11;

      // Label (R / G / B)
      final TextPainter labelTp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'Courier New',
            fontSize: 8,
            color: colors[i],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(labelX, _Layout.rgbY));

      // Numeric value — right-padded to 3 chars
      final TextPainter valTp = TextPainter(
        text: TextSpan(
          text: values[i].toString().padLeft(3),
          style: const TextStyle(
            fontFamily: 'Courier New',
            fontSize: 8,
            color: _Pal.textSec,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(valueX, _Layout.rgbY));
    }
  }

  @override
  bool shouldRepaint(ColorPickerPainter old) => true;
}
