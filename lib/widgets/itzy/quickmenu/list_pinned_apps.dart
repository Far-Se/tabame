import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/keys.dart';
import '../../widgets/bar_with_buttons.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class PinnedApps extends StatelessWidget {
  const PinnedApps({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> pinned = Boxes().pinnedApps;
    if (pinned.isEmpty) return const SizedBox();
    return BarWithButtons(children: <Widget>[
      for (String item in pinned)
        GestureDetector(
          onSecondaryTap: () {
            final int x = pinned.indexWhere((String element) => element == item);
            WinKeys.send("{#WIN}{#ALT}${x + 1}");
            if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
          },
          child: _PinnedAppButton(path: item),
        )
    ]);
  }
}

class _PinnedAppButton extends StatelessWidget {
  const _PinnedAppButton({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).iconTheme.size ?? 15;
    if (!File(path).existsSync()) return const SizedBox();
    // print(path);
    final String customIconPath = Boxes.getIconRewrite(path);

    if (customIconPath != "") {
      return SizedBox(
        width: size + 6.1,
        height: size + 6.1,
        child: InkWell(
          onTap: () {
            WinUtils.open(path);
            if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: CustomTooltip(
              message: path.substring(path.lastIndexOf('\\') + 1),
              child: RepaintBoundary(
                child: Image.file(File(customIconPath), width: 20),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: size + 6.1,
      height: size + 6.1,
      child: FutureBuilder<Uint8List?>(
        future: _loadIconBytes(path),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          return InkWell(
            onTap: () {
              WinUtils.open(path);
              if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: snapshot.hasData
                  ? CustomTooltip(
                      message: path.substring(path.lastIndexOf('\\') + 1),
                      child: RepaintBoundary(
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.scaleDown,
                          width: size,
                          gaplessPlayback: true,
                          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                            Icons.check_box_outline_blank,
                            size: 16,
                          ),
                        ),
                      ),
                    )
                  : Icon(Icons.circle_outlined, size: size),
            ),
          );
        },
      ),
    );
  }

  Future<Uint8List?> _loadIconBytes(String path) async {
    final String customIconPath = Boxes.getIconRewrite(path);
    if (customIconPath.isNotEmpty) {
      final ByteData bytes = await rootBundle.load(customIconPath);
      return bytes.buffer.asUint8List();
    }
    return Future<Uint8List?>.value(WinUtils.extractIcon(path));
  }
}
