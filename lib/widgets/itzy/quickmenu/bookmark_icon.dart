import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/win32/win_utils.dart';
import 'button_window_app.dart';

class BookmarkIcon extends StatelessWidget {
  const BookmarkIcon({
    super.key,
    required this.mark,
    this.fallbackEmoji = "",
    this.size = 14,
  });

  final BookmarkInfo mark;
  final String fallbackEmoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (mark.preferInputIcon) {
      final String path = mark.stringToExecute.trim();
      if (path.startsWith('http')) {
        return FutureBuilder<File?>(
          future: WinUtils.getFaviconUrlData(path),
          builder: (BuildContext context, AsyncSnapshot<File?> snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              final File file = snapshot.data!;
              if (file.path.toLowerCase().endsWith('.svg')) {
                return SvgPicture.file(
                  file,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                );
              }
              return Image.file(
                file,
                width: size,
                height: size,
                fit: BoxFit.contain,
              );
            }
            return _buildFallback();
          },
        );
      } else if (path.isNotEmpty &&
          (path.contains(':\\') ||
              path.contains(':/') ||
              path.endsWith('.exe') ||
              path.endsWith('.url') ||
              path.endsWith('.lnk'))) {
        return FutureBuilder<Uint8List?>(
          future: WindowsAppButton.getIcon(path),
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.contain,
              );
            }
            return _buildFallback();
          },
        );
      }
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    final String emoji = mark.emoji.isNotEmpty ? mark.emoji : (fallbackEmoji.isNotEmpty ? fallbackEmoji : "🔖");
    return Text(
      emoji,
      style: TextStyle(fontSize: size),
    );
  }
}
