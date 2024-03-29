// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class TextInput extends StatefulWidget {
  final String labelText;
  final String? hintText;
  final String? value;
  final InputDecoration? decoration;
  final void Function(String val) onChanged;
  final void Function(String val)? onSubmitted;
  final void Function(String val)? onUpdated;
  final bool multiline;
  const TextInput({
    Key? key,
    required this.labelText,
    this.hintText,
    this.value,
    required this.onChanged(String val),
    this.onSubmitted,
    this.onUpdated,
    this.multiline = false,
    this.decoration,
  }) : super(key: key);

  @override
  TextInputState createState() => TextInputState();
}

class TextInputState extends State<TextInput> {
  final TextEditingController _controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? "";
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  bool sent = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (bool value) async {
        if (value == false) {
          if (sent == false) {
            widget.onChanged(_controller.text);
            sent = true;
          }
        } else {
          sent = false;
        }
      },
      child: TextField(
        maxLines: widget.multiline ? null : 1,
        decoration: widget.decoration ??
            InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText ?? widget.labelText,
              border: InputBorder.none,
              isDense: false,
            ),
        controller: _controller,
        toolbarOptions: const ToolbarOptions(
          paste: true,
          cut: true,
          copy: true,
          selectAll: true,
        ),
        style: const TextStyle(fontSize: 14),
        enableInteractiveSelection: true,
        onSubmitted: (String e) {
          widget.onChanged(e);
          widget.onSubmitted == null ? null : widget.onSubmitted!(e);
          sent = true;
        },
        onChanged: (String e) => widget.onUpdated == null ? null : widget.onUpdated!(e),
      ),
    );
  }
}
