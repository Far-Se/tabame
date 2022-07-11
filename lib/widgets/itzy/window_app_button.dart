import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../models/win32/imports.dart';
import '../../models/win32/win32.dart';

class WindowsAppButton extends StatelessWidget {
  final String path;
  const WindowsAppButton({
    Key? key,
    required this.path,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double size = Theme.of(context).iconTheme.size ?? 12;
    if (!File(path).existsSync()) return const SizedBox();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size + 5,
        height: double.maxFinite,
        child: FutureBuilder<Uint8List?>(
          future: nativeIconToBytes(path),
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
                        ),
                      )
                    : Icon(Icons.circle_outlined, size: size),
              ),
              onTap: () {
                WinUtils.open(path);
              },
              onDoubleTap: () async {
                final Set<int> startWindows = enumWindows().toSet();
                WinUtils.open(path);
                int ticker = 0;
                Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
                  ticker++;
                  if (ticker > 10) {
                    timer.cancel();
                    return;
                  }
                  final Set<int> endWindows = enumWindows().toSet();
                  final List<int> newWnds = List<int>.from(endWindows.difference(startWindows));
                  final List<int> windows = newWnds.where(((int hWnd) => (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "") ? true : false)).toList();
                  if (windows.isEmpty) return;
                  final int hwnd = windows[0];
                  final Pointer<RECT> lpRect = calloc<RECT>();
                  GetWindowRect(Win32.hWnd, lpRect);
                  free(lpRect);
                  Win32.setCenter(hwnd: hwnd, useMouse: true);
                  timer.cancel();
                });
              },
            );
          },
        ),
      ),
    );
  }
}
