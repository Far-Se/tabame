// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/settings.dart';
import '../../../models/win32/keys.dart';

class TimeWidget extends StatefulWidget {
  final bool inline;
  const TimeWidget({
    super.key,
    this.inline = false,
  });

  @override
  State<TimeWidget> createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!QuickMenuFunctions.isQuickMenuVisible) return;
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _onTap() {
    userSettings.noopKeyListener = true;
    WinKeys.send("{#LWIN}C");
    Future<void>.delayed(const Duration(milliseconds: 500), () => userSettings.noopKeyListener = false);
  }

  @override
  Widget build(BuildContext context) {
    final String timeStr = DateFormat('hh:mm:ss').format(_now);
    final String dateStr = DateFormat('dd MMM').format(_now);
    final String dayStr = DateFormat('EE').format(_now);
    final FontWeight fontWeight = FontWeight(userSettings.theme.entryFontWeight);

    if (widget.inline) {
      return InkWell(
        onTap: _onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 5, 0, 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _buildText(timeStr, userSettings.expandedTaskbar ? 12.5 : 11.5, fontWeight, minWidth: 70, maxWidth: 100),
              _buildText("$dayStr $dateStr", userSettings.expandedTaskbar ? 12.5 : 11.5, fontWeight,
                  minWidth: 60, maxWidth: 100),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: _onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  fit: FlexFit.tight,
                  child: Center(child: _buildText(timeStr, 11.5, fontWeight)),
                ),
                Flexible(
                  fit: FlexFit.tight,
                  child: Center(child: _buildText("$dayStr $dateStr", 11.5, fontWeight)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(String text, double fontSize, FontWeight weight, {double? minWidth, double? maxWidth}) {
    Widget child = Text(
      text,
      style: GoogleFonts.getFont(User.theme.entryFontFamily, fontSize: fontSize, fontWeight: weight),
      overflow: TextOverflow.ellipsis,
    );

    if (minWidth != null || maxWidth != null) {
      child = Container(
        constraints: BoxConstraints(minWidth: minWidth ?? 0, maxWidth: maxWidth ?? double.infinity),
        child: child,
      );
    }
    return child;
  }
}
