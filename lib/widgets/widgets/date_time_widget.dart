import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';

class DateTimeWidget extends StatefulWidget {
  const DateTimeWidget({super.key, this.style, this.textAlign = TextAlign.start, this.padding = EdgeInsets.zero});

  final TextStyle? style;
  final TextAlign textAlign;
  final EdgeInsets padding;

  @override
  State<DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<DateTimeWidget> with QuickMenuTriggers {
  static const Duration _refreshInterval = Duration(seconds: 1);

  final DateFormat _dateTimeFormat = DateFormat('EEE d MMM').add_jms();
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    if (QuickMenuFunctions.isQuickMenuVisible) _startTimer();
  }

  @override
  void dispose() {
    _stopTimer();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible) {
      if (mounted) setState(() => _now = DateTime.now());
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final double windowWidth = MediaQuery.maybeOf(context)?.size.width ?? double.infinity;
    if (windowWidth < 400) return const SizedBox.shrink();

    return Padding(
      padding: widget.padding,
      child: Text(
        _dateTimeFormat.format(_now),
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
  }
}
