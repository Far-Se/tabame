import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../itzy/audio_button.dart';
import '../itzy/simulate_key_button.dart';
import 'bar_with_buttons.dart';

class TopBar extends StatelessWidget {
  const TopBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: BarWithButtons(
            children: [
              InkWell(
                onTap: () {
                  WindowManager.instance.close();
                },
                child: Icon(Icons.close),
              ),
              SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D", color: Colors.grey.shade300),
              AudioButton(),
            ],
          )),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 50,
              child: BarWithButtons(
                children: [
                  SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D", color: Colors.grey.shade300),
                  SimulateKeyButton(icon: Icons.settings, simulateKeys: "{#WIN}", color: Colors.grey.shade300),
                ],
                withScroll: false,
              ),
            ),
          )
        ],
      ),
    );
  }
}
