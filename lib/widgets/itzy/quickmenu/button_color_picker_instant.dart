import 'package:flutter/material.dart';

import '../../../pages/color_picker/win32_helper.dart';
import '../../widgets/quick_actions_item.dart';

class ColorPickerInstantButton extends StatelessWidget {
  const ColorPickerInstantButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Instant Color Picker",
      icon: const Icon(Icons.colorize_sharp),
      onTap: () async {
        await Win32Helper.instantColorPicker();
      },
    );
  }
}
