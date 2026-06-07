import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class SystemUsageWidget extends StatefulWidget {
  const SystemUsageWidget({super.key});

  @override
  SystemUsageWidgetState createState() => SystemUsageWidgetState();
}

class SystemUsageWidgetState extends State<SystemUsageWidget> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    getSystemResourcesInfo().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        getSystemResourcesInfo();
        if (!mounted) return;
        setState(() {});
      }
    });
  }

  String cpuUsage = '0%';
  String memUsage = '0%';
  Future<void> getSystemResourcesInfo() async {
    final List<dynamic> output = await getSystemUsage();
    cpuUsage = "${(output[0] * 100).toStringAsFixed(0)}%";
    memUsage = "${output[1]}%";
    return;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text("📟$cpuUsage\n💾$memUsage",
        style: TextStyle(fontSize: Design.baseFontSize + 2, height: 1.1), softWrap: false);
  }
}
