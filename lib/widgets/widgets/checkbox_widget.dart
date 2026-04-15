import 'package:flutter/material.dart';

class CheckBoxWidget extends StatefulWidget {
  final Function(bool) onChanged;
  final bool value;
  final String text;

  final EdgeInsets padding;
  const CheckBoxWidget({
    super.key,
    required this.onChanged,
    required this.value,
    required this.text,
    this.padding = EdgeInsets.zero,
  });

  @override
  CheckBoxWidgetState createState() => CheckBoxWidgetState();
}

class CheckBoxWidgetState extends State<CheckBoxWidget> {
  bool checked = false;
  @override
  void initState() {
    checked = widget.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        checked = !checked;
        widget.onChanged(checked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: widget.padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(width: 25, child: Icon(checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.text,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
