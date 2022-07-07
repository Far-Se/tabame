// ignore_for_file: public_member_api_docs, sort_constructors_first
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
    final size = Theme.of(context).iconTheme.size ?? 12;
    // final color = Theme.of(context).iconTheme.size;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size + 5,
        child: FutureBuilder(
          future: nativeIconToBytes(path),
          builder: (context, snapshot) {
            return InkWell(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: snapshot.data is Uint8List
                    ? Image.memory(
                        snapshot.data! as Uint8List,
                        fit: BoxFit.scaleDown,
                        width: size,
                        gaplessPlayback: true,
                      )
                    : Icon(Icons.circle_outlined, size: size),
              ),
              onTap: () {
                Process.run(path, []);
              },
              onDoubleTap: () async {
                final startWindows = enumWindows().toSet();
                await Process.start(path, []);
                int ticker = 0;
                Timer.periodic(Duration(milliseconds: 100), (timer) {
                  ticker++;
                  if (ticker > 10) {
                    timer.cancel();
                    return;
                  }
                  final endWindows = enumWindows().toSet();
                  final newWnds = List.from(endWindows.difference(startWindows));
                  final windows = newWnds.where(((hWnd) => (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "") ? true : false)).toList();
                  if (windows.isEmpty) return;
                  final hwnd = windows[0];
                  final lpRect = calloc<RECT>();
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
