import 'dart:io';

import 'package:flutter/material.dart';

class SystemUsageWidget extends StatefulWidget {
  const SystemUsageWidget({Key? key}) : super(key: key);

  @override
  SystemUsageWidgetState createState() => SystemUsageWidgetState();
}

late Process process;
String cpuUsage = '0%';
String memUsage = '0%';
void runPowerShellCpu() async {
  process = await Process.start(
    "powershell",
    <String>[
      '-NoProfile',
      // '-executionPolicy bypass',
      '\n\$totalRam = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).Sum;',
      '''\nwhile(\$true) {
    \$cpu = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select Average) | Select-String -Pattern "[0-9]*";
    \$mem = (Get-Counter "\\Memory\\Available MBytes").CounterSamples.CookedValue;
    '' + \$cpu +'[' +  (104857600 * \$mem / \$totalRam).ToString("#,0.0") + ']';
    Start-Sleep -s 2;
}''',
    ],
  );
  process.stdout.listen((List<int> event) {
    //regex match @{Average=[0-9]*}
    final String output = String.fromCharCodes(event);
    if (output == "") return;
    RegExp regex = RegExp(r'Average=([0-9]+)');
    if (regex.hasMatch(output)) {
      RegExpMatch match = regex.firstMatch(output)!;
      cpuUsage = '${match.group(1)}%';
      regex = RegExp(r'\[([0-9.]+)\]');
      match = regex.firstMatch(output)!;
      memUsage = '${match.group(1)}%';
    }
  });
}

class SystemUsageWidgetState extends State<SystemUsageWidget> {
  @override
  void initState() {
    super.initState();
    runPowerShellCpu();
  }

  @override
  void dispose() {
    process.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
        stream: Stream<String>.periodic(const Duration(seconds: 2), (_) => cpuUsage),
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) => Text(
              "🏼$cpuUsage\n💾$memUsage",
              style: const TextStyle(fontSize: 11, height: 1.1),
              softWrap: false,
            ));
  }
}
