import 'package:flutter/material.dart';
// import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

class Interface extends StatefulWidget {
  const Interface({Key? key}) : super(key: key);

  @override
  InterfaceState createState() => InterfaceState();
}

class InterfaceState extends State<Interface> {
  @override
  void initState() {
    WindowManager.instance.setPosition(const Offset(200, 200), animate: true);
    WindowManager.instance.setSize(const Size(500, 500));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Interface'),
      ),
      body: Container(
        width: 500,
        height: 300,
        child: Center(
          child: Text("TEST"),
        ),
      ),
    );
  }
}
