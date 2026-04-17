// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class TestingButton extends StatelessWidget {
  const TestingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 21,
        child: IconButton(
          iconSize: 16,
          padding: const EdgeInsets.all(0),
          splashRadius: 16,
          icon: const CustomTooltip(
            message: "Testing",
            child: Icon(Icons.textsms_outlined),
          ),
          onPressed: () async {
            print(Boxes.quickGrids[0].toJson());
          },
        ),
      ),
    );
  }
}
