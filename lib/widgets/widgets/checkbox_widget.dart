import 'package:flutter/material.dart';

class CheckBoxWidget extends StatefulWidget {
  final Function(bool) onTap;
  final bool value;
  final String text;
  const CheckBoxWidget({
    Key? key,
    required this.onTap,
    required this.value,
    required this.text,
  }) : super(key: key);

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
        widget.onTap(checked);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(width: 25, child: Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: 18)),
          Expanded(child: Text(widget.text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
