import 'package:flutter/material.dart';

import '../../widgets/color_picker_panel.dart';
import '../../widgets/modal_button.dart';

class ColorPickerButton extends StatelessWidget {
  const ColorPickerButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Color Picker", icon: const Icon(Icons.palette_outlined), child: () => const ColorPickerPanel());
  }
}
