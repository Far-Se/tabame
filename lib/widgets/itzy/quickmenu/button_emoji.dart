import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../widgets/emoji_picker_modal.dart';
import '../../widgets/modal_button.dart';

class EmojiButton extends StatelessWidget {
  const EmojiButton({super.key});

  Future<void> _handleEmojiSelected(String emoji) async {
    await Clipboard.setData(ClipboardData(text: emoji));
    QuickMenuFunctions.hideQuickMenu();
  }

  Future<void> _closeEmojiPicker() async {
    QuickMenuFunctions.hideQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Emoji",
      icon: const Icon(Icons.emoji_emotions_outlined),
      child: () => EmojiPickerModal(
        title: "Emoji Picker",
        quickTip: "Press Ctrl+V if it doesn't paste",
        onEmojiSelected: _handleEmojiSelected,
        userPredefined: false,
        onCloseRequested: _closeEmojiPicker,
      ),
    );
  }
}
