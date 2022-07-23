import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

class SystemUsageWidget extends StatefulWidget {
  const SystemUsageWidget({Key? key}) : super(key: key);

  @override
  SystemUsageWidgetState createState() => SystemUsageWidgetState();
}

String cpuUsage = '0%';
String memUsage = '0%';
Future<void> getSystemResourcesInfo() async {
  final List<dynamic> output = await getSystemUsage();
  cpuUsage = "${(output[0] * 100).toStringAsFixed(0)}%";
  memUsage = "${output[1]}%";
  return;
}

class SystemUsageWidgetState extends State<SystemUsageWidget> {
  @override
  void initState() {
    super.initState();
    getSystemResourcesInfo().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
        stream: Stream<String>.periodic(const Duration(seconds: 2), (_) => cpuUsage),
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) => FutureBuilder<void>(
              future: getSystemResourcesInfo(),
              builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) => Text(
                "🏼$cpuUsage\n💾$memUsage",
                style: const TextStyle(fontSize: 11, height: 1.1),
                softWrap: false,
              ),
            ));
  }
}
