import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/win32.dart';

class WindowsAppButton extends StatelessWidget {
  final String path;
  const WindowsAppButton({
    Key? key,
    required this.path,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).iconTheme.size ?? 15;
    if (!File(path).existsSync()) return const SizedBox();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    return SizedBox(
      width: size + 5,
      height: double.maxFinite,
      child: FutureBuilder<Uint8List?>(
        future: getExecutableIcon(path),
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          return InkWell(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: snapshot.data is Uint8List
                  ? Tooltip(
                      message: path.substring(path.lastIndexOf('\\') + 1),
                      child: Image.memory(
                        snapshot.data! as Uint8List,
                        fit: BoxFit.scaleDown,
                        width: size,
                        gaplessPlayback: true,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                          Icons.check_box_outline_blank,
                          size: 16,
                        ),
                      ),
                    )
                  : Icon(Icons.circle_outlined, size: size),
            ),
            onTap: () {
              WinUtils.openAndFocus(path, centered: true, usePowerShell: true);
              // WinUtils.shellOpen(path);
              if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
            },
          );
        },
      ),
    );
  }
}
