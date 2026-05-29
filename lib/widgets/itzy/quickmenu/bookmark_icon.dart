import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/extracted_icon.dart';
import 'button_window_app.dart';

class BookmarkIcon extends StatelessWidget {
  const BookmarkIcon({
    super.key,
    required this.mark,
    this.fallbackEmoji = "",
    this.size = 14,
  });
  static final Map<String, String> iconExtCache = <String, String>{};
  final BookmarkInfo mark;
  final String fallbackEmoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (mark.preferInputIcon) {
      final String path = mark.stringToExecute.trim();
      final String lowerPath = path.toLowerCase();
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
                cacheHeight: size.toInt(),
                cacheWidth: size.toInt(),
                fit: BoxFit.contain,
              );
            }
            return _buildFallback();
          },
        );
      } else if (path.isNotEmpty &&
          (path.contains(':\\') ||
              path.contains(':/') ||
              lowerPath.endsWith('.exe') ||
              lowerPath.endsWith('.url') ||
              lowerPath.endsWith('.lnk'))) {
        File? file = WinUtils.getCachedFileFormatIcon(path);
        file ??= File('${WinUtils.getTabameAppDataFolder()}/cache/icon_cache/${path.hashCode}.ico');
        if (!lowerPath.endsWith('.exe') && !lowerPath.endsWith('.url') && !lowerPath.endsWith('.lnk')) {
          final String ext = path.split('.').last.toLowerCase();
          if (iconExtCache.containsKey(ext)) {
            file = File(iconExtCache[ext]!);
          }
        }
        if (file.existsSync()) {
          final DateTime lastModified = file.lastModifiedSync();
          if (DateTime.now().difference(lastModified).inDays < 7) {
            return Image.file(
              file,
              width: size,
              height: size,
              cacheHeight: size.toInt(),
              cacheWidth: size.toInt(),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                return _buildFallback();
              },
            );
          }
        }
        return FutureBuilder<ExtractedIcon>(
          future: WindowsAppButton.getIcon(path),
          builder: (BuildContext context, AsyncSnapshot<ExtractedIcon> snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              if (snapshot.data case final String xpath when xpath.isNotEmpty) {
                if (!lowerPath.endsWith('.exe') && !lowerPath.endsWith('.url') && !lowerPath.endsWith('.lnk')) {
                  try {
                    final String file = path.split('\\').last;
                    if (file.contains('.')) {
                      final String ext = file.split('.').last.toLowerCase();
                      if (!iconExtCache.containsKey(ext)) {
                        iconExtCache[ext] = snapshot.data as String;
                      }
                    }
                  } catch (_) {}
                }
              }
              return buildExtractedIcon(
                snapshot.data,
                width: size,
                height: size,
                cacheHeight: size.toInt(),
                cacheWidth: size.toInt(),
                fit: BoxFit.contain,
                fallback: _buildFallback(),
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
