// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class InfoWidget extends StatelessWidget {
  final Function() onTap;
  final String text;
  const InfoWidget(
    this.text, {
    Key? key,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(),
      child: Tooltip(message: text, child: Icon(Icons.info_outline, color: Theme.of(context).toggleableActiveColor)),
    );
  }
}
