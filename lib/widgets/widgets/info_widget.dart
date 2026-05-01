// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import 'custom_tooltip.dart';

class InfoWidget extends StatelessWidget {
  final Function() onTap;
  final String text;
  const InfoWidget(
    this.text, {
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(),
      child:
          CustomTooltip(message: text, child: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary)),
    );
  }
}
