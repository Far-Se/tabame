final List<Map<String, dynamic>> mainHotkeyData = <Map<String, dynamic>>[
  <String, dynamic>{
    "key": "P",
    "modifiers": <String>["CTRL", "ALT", "SHIFT"],
    "keymaps": <Map<String, Object>>[
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Start Menu Rightclick menu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 2},
        "triggerType": 3,
        "triggerInfo": <int>[200, 700, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}X"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Full Screen",
        "windowsInfo": <String>["title", "(chrome|firefox|brave|edge)"],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 99, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": <int>[200, 1000, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{F11}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Open Tab",
        "windowsInfo": <String>["exe", "(chrome|firefox|brave|edge)"],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 100, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#CTRL}t"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Desktop",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 3},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}D"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show StartMenu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 57, "y2": 57, "asPercentage": false, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#CTRL}{ESC}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Toggle Taskbar",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 3, "y1": 0, "x2": 100, "y2": 5, "asPercentage": true, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ToggleTaskbar"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move to Right Desktop",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[1, 500, 9999],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}{#CTRL}{RIGHT}{|}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move To Left Desktop",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[0, 500, 9999],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}{#CTRL}{LEFT}{|}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Launcher",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[1, 100, 300],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "OpenLauncher"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Down",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[3, 15, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{VOLUME_DOWN}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Up",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[2, 15, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{VOLUME_UP}{VOLUME_UP}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": false,
        "windowUnderMouse": false,
        "name": "Show Last Active Window",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 1,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ShowSecondWindowUnderCursor"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Tabame Function: ShowLastWindowUnderCursor Via Hold Duration",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": <int>[110, 1000, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ShowLastWindowUnderCursor"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Tabame",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ToggleQuickMenu"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Window Actions Menu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 1, "y1": 0, "x2": 1, "y2": 99, "asPercentage": true, "anchorType": 1},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}A"}
        ],
        "variableCheck": <String>["", ""]
      }
    ],
    "prohibited": <String>[""],
    "noopScreenBusy": false,
    "waitForDoublePress": false
  }
];
final List<Map<String, dynamic>> mainHotkeyDataOld = <Map<String, dynamic>>[
  <String, dynamic>{
    "key": "F9",
    "modifiers": <String>["CTRL", "ALT"],
    "keymaps": <Map<String, Object>>[
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Start Menu Rightclick menu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 2},
        "triggerType": 3,
        "triggerInfo": <int>[200, 700, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}X"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Close Tab",
        "windowsInfo": <String>["title", "(chrome|firefox|brave|edge)"],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 99, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": <int>[200, 1000, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{MMB}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Open Tab",
        "windowsInfo": <String>["exe", "(chrome|firefox|brave|edge)"],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 100, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#CTRL}t"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Desktop",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 3},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}D"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show StartMenu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 57, "y2": 57, "asPercentage": false, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ShowStartMenu"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Toggle Taskbar",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 3, "y1": 0, "x2": 100, "y2": 5, "asPercentage": true, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ToggleTaskbar"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Actions Menu",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": true,
        "region": <String, Object>{"x1": 1, "y1": 0, "x2": 1, "y2": 99, "asPercentage": true, "anchorType": 1},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{#WIN}A"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move Desktop to Left",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[0, 400, 9999],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "SwitchDesktopToLeft"},
          <String, Object>{"type": 3, "value": "[\"desktop\",\"Left\"]"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move Desktop To Right",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[1, 400, 9999],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "SwitchDesktopToRight"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Fancyshot",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[0, 100, 400],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "FancyShot"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Interface",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[1, 100, 400],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 5, "value": "Interface"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Down",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[3, 30, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{VOLUME_DOWN}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Up",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": <int>[2, 30, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 0, "value": "{VOLUME_UP}"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Last Active Window",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 1,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ShowSecondWindowUnderCursor"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show StartMenu Hold",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": <int>[200, 500, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ShowStartMenu"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Tabame",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, -1],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "ToggleQuickMenu"}
        ],
        "variableCheck": <String>["", ""]
      }
    ],
    "prohibited": <String>[""],
    "noopScreenBusy": false
  },
  <String, dynamic>{
    "key": "A",
    "modifiers": <String>["CTRL", "ALT", "SHIFT"],
    "keymaps": <Map<String, Object>>[
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Audio Box",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": <int>[0, 300, 2000],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "OpenAudioSettings"}
        ],
        "variableCheck": <String>["", ""]
      },
      <String, Object>{
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Switch Audio Output",
        "windowsInfo": <String>["any", ""],
        "boundToRegion": false,
        "region": <String, Object>{"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": <int>[0, 0, 0],
        "actions": <Map<String, Object>>[
          <String, Object>{"type": 2, "value": "SwitchAudioOutput"}
        ],
        "variableCheck": <String>["", ""]
      }
    ],
    "prohibited": <dynamic>[],
    "noopScreenBusy": false
  }
];
