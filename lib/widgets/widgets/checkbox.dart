// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class CustomCheckbox extends StatefulWidget {
  final bool value;
  final IconData icon;
  final Function onChanged;
  const CustomCheckbox({
    Key? key,
    required this.value,
    required this.icon,
    required this.onChanged,
  }) : super(key: key);

  @override
  CustomCheckboxState createState() => CustomCheckboxState();
}

class CustomCheckboxState extends State<CustomCheckbox> {
  @override
  Widget build(BuildContext context) {
    bool value = widget.value;
    return InkWell(

        ///CHECKBOX
        onTap: () {
          widget.onChanged();
          setState(() {
            value = !value;
          });
        },
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: value
              ? Container(
                  padding: const EdgeInsets.all(5.0),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                  child: Icon(
                    widget.icon,
                    size: 20.0,
                    color: Colors.white,
                  ))
              : Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                  padding: const EdgeInsets.all(0.0),
                  child: const Icon(
                    Icons.circle,
                    size: 30.0,
                    color: Colors.white,
                  ),
                ),
        ));
  }
}
