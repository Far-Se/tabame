import 'package:flutter/material.dart';

class InfoText extends StatelessWidget {
  final String text;
  const InfoText(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontStyle: FontStyle.italic,
        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
      ),
    );
  }
}
