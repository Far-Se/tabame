import 'package:flutter/material.dart';

import 'quickmenu.dart';
// import 'package:win32/win32.dart';

class Interface extends StatefulWidget {
  const Interface({Key? key}) : super(key: key);

  @override
  InterfaceState createState() => InterfaceState();
}

class InterfaceState extends State<Interface> {
  @override
  void initState() {
    // WindowManager.instance.setPosition(const Offset(200, 200), animate: true);
    // WindowManager.instance.setSize(const Size(500, 500));
    // Win32().setCenter(useMouse: true, hwnd: Win32().hWnd);

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interface'),
      ),
      body: Container(
        width: 500,
        height: 300,
        child: IconButton(
          padding: const EdgeInsets.all(0),
          splashRadius: 25,
          icon: const Icon(
            Icons.settings,
          ),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<QuickMenu>(maintainState: false, builder: (BuildContext context) => const QuickMenu()),
              (Route<dynamic> route) => false,
            );
          },
        ),
      ),
    );
  }
}
