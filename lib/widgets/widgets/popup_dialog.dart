import 'package:flutter/material.dart';

void popupDialog(BuildContext context, String str) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content:
            Container(height: 50 + ("\n".allMatches(str).length.clamp(0, 10).toDouble() * 20), child: Center(child: Text(str, style: const TextStyle(fontSize: 20)))),
        actions: <Widget>[
          ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text("Ok", style: TextStyle(color: Theme.of(context).colorScheme.primary))),
        ],
      );
    },
  ).then((_) {});
}
