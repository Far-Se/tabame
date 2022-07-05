// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

class WindowsAppButton extends StatelessWidget {
  final String path;
  const WindowsAppButton({
    Key? key,
    required this.path,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 25,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: FutureBuilder(
            future: nativeIconToBytes(path),
            builder: (context, snapshot) {
              return InkWell(
                child: snapshot.data is Uint8List ? Image.memory(snapshot.data! as Uint8List, fit: BoxFit.scaleDown) : Icon(Icons.circle_outlined, size: 15),
                onTap: () {
                  Process.run(path, []);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
