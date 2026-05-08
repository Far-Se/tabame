import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/keys.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/windows_scroll.dart';

class PinnedApps extends StatelessWidget {
  const PinnedApps({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> pinned = Boxes.pinnedApps;
    if (pinned.isEmpty) return const SizedBox();
    return WindowsScrollView(
      scrollDirection: Axis.horizontal,
      showScrollbar: false,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      friction: 0.5,
      child: Row(children: <Widget>[
        for (String item in pinned)
          GestureDetector(
            onSecondaryTap: () {
              final int x = pinned.indexWhere((String element) => element == item);
              WinKeys.send("{#WIN}{#ALT}${x + 1}");
              if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
            },
            child: _PinnedAppButton(path: item),
          )
      ]),
    );
  }
}

class _PinnedAppButton extends StatelessWidget {
  const _PinnedAppButton({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).iconTheme.size ?? 14.3;
    if (!File(path).existsSync()) return const SizedBox();
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
      child: FutureBuilder<ExtractedIcon>(
        future: _loadIcon(path),
        builder: (BuildContext context, AsyncSnapshot<ExtractedIcon> snapshot) {
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
                        child: buildExtractedIcon(
                          snapshot.data,
                          fit: BoxFit.scaleDown,
                          width: size,
                          gaplessPlayback: true,
                          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                              const Icon(Icons.check_box_outline_blank, size: 16),
                          fallback: const Icon(Icons.check_box_outline_blank, size: 16),
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

  Future<ExtractedIcon> _loadIcon(String path) async {
    return Future<ExtractedIcon>.value(WinUtils.extractIcon(path));
  }
}
