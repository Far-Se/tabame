import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import 'panel_header.dart';

class BMACDialog extends StatelessWidget {
  const BMACDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final ThemeData theme = Theme.of(context);
    final Color surface = theme.colorScheme.surface;

    return Center(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              color: surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PanelHeader(
                  title: "Support Tabame",
                  accent: accent,
                  icon: Icons.favorite_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    children: <Widget>[
                      Text(
                        "Tabame is provided for free. If you find it useful, your support helps maintain the project.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 24),
                      InkWell(
                        onTap: () {
                          WinUtils.open("https://www.buymeacoffee.com/far.se");
                          Boxes.pref.setBool("bmacPopup", true);
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.coffee_rounded, size: 18, color: accent),
                              const SizedBox(width: 10),
                              Text(
                                "Buy me a Coffee",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          Boxes.pref.setBool("bmacPopup", true);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            "Don't show again",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
