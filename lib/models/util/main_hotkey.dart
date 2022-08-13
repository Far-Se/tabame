// ignore_for_file: always_specify_types

final List<Map<String, dynamic>> hotkeyMap = <Map<String, dynamic>>[
  {
    "key": "F9",
    "modifiers": ["CTRL", "ALT"],
    "keymaps": [
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Start Menu Rightclick menu",
        "windowsInfo": ["any", ""],
        "boundToRegion": true,
        "region": {"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 2},
        "triggerType": 3,
        "triggerInfo": [200, 700, 0],
        "actions": [
          {"type": 0, "value": "{#WIN}X"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Open Tab",
        "windowsInfo": ["exe", "(chrome|firefox)"],
        "boundToRegion": true,
        "region": {"x1": 0, "y1": 0, "x2": 100, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": [200, 1000, 0],
        "actions": [
          {"type": 0, "value": "{#CTRL}t"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Browser Close Tab",
        "windowsInfo": ["title", "(chrome|firefox)"],
        "boundToRegion": true,
        "region": {"x1": 0, "y1": 0, "x2": 99, "y2": 6, "asPercentage": true, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 0, "value": "{MMB}"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Desktop",
        "windowsInfo": ["any", ""],
        "boundToRegion": true,
        "region": {"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 3},
        "triggerType": 0,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 0, "value": "{#WIN}D"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show StartMenu",
        "windowsInfo": ["any", ""],
        "boundToRegion": true,
        "region": {"x1": 0, "y1": 0, "x2": 57, "y2": 57, "asPercentage": false, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 0, "value": "{WIN}"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Toggle Taskbar",
        "windowsInfo": ["any", ""],
        "boundToRegion": true,
        "region": {"x1": 3, "y1": 0, "x2": 100, "y2": 5, "asPercentage": true, "anchorType": 2},
        "triggerType": 0,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 2, "value": "ToggleTaskbar"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move Desktop to Left",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": [0, 400, 9999],
        "actions": [
          {"type": 2, "value": "SwitchDesktopToLeft"},
          {"type": 3, "value": "[\"desktop\",\"Left\"]"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Move Desktop To Right",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": [1, 400, 9999],
        "actions": [
          {"type": 2, "value": "SwitchDesktopToRight"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Down",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": [3, 30, -1],
        "actions": [
          {"type": 0, "value": "{VOLUME_DOWN}"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Volume Up",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 2,
        "triggerInfo": [2, 30, -1],
        "actions": [
          {"type": 0, "value": "{VOLUME_UP}"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show Last Active Window",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 1,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 2, "value": "ShowLastActiveWindow"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Show StartMenu Hold",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": [200, 500, 0],
        "actions": [
          {"type": 0, "value": "{WIN}"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Tabame",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": [0, 0, -1],
        "actions": [
          {"type": 2, "value": "ToggleQuickMenu"}
        ],
        "variableCheck": ["", ""]
      }
    ],
    "prohibited": [""],
    "noopScreenBusy": false
  },
  {
    "key": "A",
    "modifiers": ["CTRL", "ALT", "SHIFT"],
    "keymaps": [
      {
        "enabled": true,
        "windowUnderMouse": false,
        "name": "Open Audio Box",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 3,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 2, "value": "ToggleTaskbar"}
        ],
        "variableCheck": ["", ""]
      },
      {
        "enabled": true,
        "windowUnderMouse": true,
        "name": "Switch Audio Output",
        "windowsInfo": ["any", ""],
        "boundToRegion": false,
        "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
        "triggerType": 0,
        "triggerInfo": [0, 0, 0],
        "actions": [
          {"type": 2, "value": "SwitchAudioOutput"}
        ],
        "variableCheck": ["", ""]
      }
    ],
    "prohibited": [],
    "noopScreenBusy": false
  }
];
