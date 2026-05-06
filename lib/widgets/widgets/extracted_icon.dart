import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

Widget buildExtractedIcon(
  Object? icon, {
  double? width,
  double? height,
  BoxFit? fit,
  int? cacheWidth,
  int? cacheHeight,
  bool gaplessPlayback = false,
  FilterQuality filterQuality = FilterQuality.low,
  ImageErrorWidgetBuilder? errorBuilder,
  Widget? fallback,
}) {
  if (icon case final Uint8List bytes when bytes.isNotEmpty) {
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }

  if (icon case final String path when path.isNotEmpty) {
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }

  return fallback ?? const SizedBox.shrink();
}
