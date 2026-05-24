import 'package:flutter/material.dart';

import '../../models/settings.dart';

class CustomTextField extends StatefulWidget {
  final String labelText;
  final String? hintText;
  final String? value;
  final void Function(String val) onChanged;
  final IconData? iconData;
  final Widget? icon;
  const CustomTextField({
    super.key,
    required this.labelText,
    this.hintText,
    this.iconData,
    this.icon,
    this.value,
    required this.onChanged(String val),
  });

  @override
  CustomTextFieldState createState() => CustomTextFieldState();
}

class CustomTextFieldState extends State<CustomTextField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.labelText,
      textField: true,
      container: true,
      child: Focus(
        onKeyEvent: (FocusNode e, KeyEvent x) {
          widget.onChanged(_controller.text);
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onChanged: widget.onChanged, // <-- important
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,

            // Use labelText instead of hintText
            labelText: widget.labelText,
            hintText: widget.hintText,

            // Makes label float when text exists
            floatingLabelBehavior: FloatingLabelBehavior.auto,

            labelStyle: TextStyle(
              fontSize: 12,
              color: userSettings.themeColors.textColor.withAlpha(110),
            ),

            prefixIcon: widget.iconData != null
                ? Icon(
                    widget.iconData,
                    size: 16,
                    color: userSettings.themeColors.accentColor,
                  )
                : widget.icon ??
                    Icon(
                      Icons.edit,
                      size: 16,
                      color: userSettings.themeColors.accentColor,
                    ),

            filled: true,
            fillColor: userSettings.themeColors.accentColor.withAlpha(10),

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: userSettings.themeColors.accentColor.withAlpha(90),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(CustomTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value ?? "";
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? "";
  }
}
